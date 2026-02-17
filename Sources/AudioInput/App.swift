import AppKit
import Combine
import SwiftUI

@main
struct AudioInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appDelegate.appState, settings: appDelegate.settings)
        } label: {
            Image(systemName: appDelegate.appState.isRecording ? "mic.fill" : "mic")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(appDelegate.appState.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let settings = AppSettings.shared
    let recorder = AudioRecorder()
    let textInserter = TextInserter()
    let hotkeyManager = HotkeyManager()

    private var overlayWindow: NSWindow?
    private var audioLevelCancellable: AnyCancellable?
    private var silenceDetectionCancellable: AnyCancellable?
    private var silenceStartTime: Date?
    private var transcriptionTask: Task<Void, Never>?
    private var lastRecordingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.loadHistory()
        checkPermissions()
        registerHotkey()
        observeAudioLevel()
        observeSilence()
        playStartupSound()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        audioLevelCancellable?.cancel()
        silenceDetectionCancellable?.cancel()
        dismissOverlay()
    }

    // MARK: - Permissions

    private func checkPermissions() {
        appState.accessibilityPermission = PermissionChecker.accessibilityStatus()
        appState.micPermission = PermissionChecker.microphoneStatus()

        if case .notDetermined = appState.micPermission {
            Task {
                let granted = await PermissionChecker.requestMicrophoneAccess()
                appState.micPermission = granted ? .granted : .denied
            }
        }

        if case .denied = appState.accessibilityPermission {
            PermissionChecker.requestAccessibilityAccess()
        }
    }

    // MARK: - Audio Level Observation

    private func observeAudioLevel() {
        audioLevelCancellable = recorder.$audioLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.appState.audioLevel = level
            }
    }

    // MARK: - Silence Detection

    private func observeSilence() {
        silenceDetectionCancellable = recorder.$rawRMS
            .receive(on: RunLoop.main)
            .sink { [weak self] rms in
                guard let self = self else { return }
                guard self.settings.silenceDetectionEnabled,
                      self.settings.recordingMode == .toggle,
                      self.appState.isRecording else {
                    self.silenceStartTime = nil
                    return
                }

                if rms < self.settings.silenceThreshold {
                    if self.silenceStartTime == nil {
                        self.silenceStartTime = Date()
                    } else if let start = self.silenceStartTime,
                              Date().timeIntervalSince(start) >= self.settings.silenceDuration {
                        self.silenceStartTime = nil
                        self.stopRecordingAndTranscribe()
                    }
                } else {
                    self.silenceStartTime = nil
                }
            }
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        hotkeyManager.register(
            keyCode: settings.hotkeyCode,
            modifiers: settings.hotkeyModifiers,
            onKeyDown: { [weak self] in
                guard let self = self else { return }
                // Cancel transcription if in progress
                if self.appState.isTranscribing {
                    self.cancelTranscription()
                    return
                }
                switch self.settings.recordingMode {
                case .pushToTalk:
                    self.startRecording()
                case .toggle:
                    if self.appState.isRecording {
                        self.stopRecordingAndTranscribe()
                    } else {
                        self.startRecording()
                    }
                }
            },
            onKeyUp: { [weak self] in
                guard let self = self else { return }
                if self.settings.recordingMode == .pushToTalk && self.appState.isRecording {
                    self.stopRecordingAndTranscribe()
                }
            }
        )
    }

    // MARK: - Recording

    private func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if let url = lastRecordingURL {
            recorder.cleanup(url: url)
            lastRecordingURL = nil
        }
        appState.status = .error("キャンセルしました")
        showOverlayBriefly()
    }

    private func startRecording() {
        guard !appState.isRecording else { return }

        // Check microphone permission
        let micStatus = PermissionChecker.microphoneStatus()
        appState.micPermission = micStatus
        if case .denied = micStatus {
            appState.status = .error("マイクの使用が許可されていません。システム設定で許可してください")
            showOverlayBriefly()
            return
        }

        // Verify selected device is still available, fallback to system default
        var deviceID = settings.selectedInputDeviceID
        if let id = deviceID {
            let available = AudioRecorder.availableInputDevices()
            if !available.contains(where: { $0.id == id }) {
                deviceID = nil
            }
        }

        do {
            _ = try recorder.startRecording(inputDeviceID: deviceID)
            appState.status = .recording
            appState.recordingStartTime = Date()
            NSSound.tink?.play()
            showOverlay()
        } catch {
            appState.status = .error("録音開始失敗: \(error.localizedDescription)")
            showOverlayBriefly()
        }
    }

    private func stopRecordingAndTranscribe() {
        guard appState.isRecording else { return }

        appState.recordingStartTime = nil

        guard let result = recorder.stopRecording() else {
            appState.status = .error("録音データなし")
            showOverlayBriefly()
            return
        }

        lastRecordingURL = result.url

        NSSound.pop?.play()

        // Skip very short recordings (< 0.3 seconds)
        if result.duration < 0.3 {
            recorder.cleanup(url: result.url)
            appState.status = .error("録音が短すぎます")
            showOverlayBriefly()
            return
        }

        appState.status = .transcribing

        let transcriber = createTranscriber()
        let language = settings.language
        let provider = settings.provider
        let processingMode = settings.textProcessingMode
        let customPrompt = settings.customPrompt
        let processorKey = settings.openAIKey

        transcriptionTask = Task { @MainActor in
            do {
                try Task.checkCancellation()
                var text = try await RetryHelper.withRetry {
                    try await transcriber.transcribe(
                        audioURL: result.url, language: language)
                }

                try Task.checkCancellation()

                // Apply text processing if enabled
                if processingMode != .none {
                    appState.status = .processing
                    let processor = TextProcessor(apiKey: processorKey)
                    let inputText = text
                    do {
                        text = try await RetryHelper.withRetry {
                            try await processor.process(text: inputText, mode: processingMode, customPrompt: customPrompt)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // テキスト整形に失敗した場合、元のテキストをそのまま使用
                        NSSound(named: "Basso")?.play()
                    }
                }

                try Task.checkCancellation()

                let record = TranscriptionRecord(
                    text: text,
                    date: Date(),
                    duration: result.duration,
                    provider: provider
                )
                appState.addRecord(record)

                await textInserter.insert(text: text)

                appState.status = .success(text)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if case .success = appState.status {
                        appState.status = .idle
                        dismissOverlay()
                    }
                }
            } catch is CancellationError {
                // Already handled in cancelTranscription()
            } catch {
                let errorMsg =
                    (error as? TranscriptionError)?.errorDescription
                    ?? error.localizedDescription
                appState.status = .error(errorMsg)
                showOverlayBriefly()
            }

            recorder.cleanup(url: result.url)
            lastRecordingURL = nil
            transcriptionTask = nil
        }
    }

    private func createTranscriber() -> TranscriptionService {
        switch settings.provider {
        case .openAI:
            OpenAITranscriber(apiKey: settings.openAIKey)
        case .gemini:
            GeminiTranscriber(apiKey: settings.geminiKey)
        }
    }

    // MARK: - Sound

    private func playStartupSound() {
        NSSound(named: "Glass")?.play()
    }

    // MARK: - Overlay Window

    private func showOverlay() {
        if overlayWindow == nil {
            let hostingView = NSHostingView(
                rootView: OverlayContainer(appState: appState))

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 52),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = true

            // Position at top center of the screen containing the mouse pointer
            let mouseScreen = NSScreen.screens.first(where: {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            }) ?? NSScreen.main
            if let screen = mouseScreen {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 140
                let y = screenFrame.maxY - 70
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            overlayWindow = window
        }

        // Update position to current active screen each time
        if let window = overlayWindow {
            let mouseScreen = NSScreen.screens.first(where: {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            }) ?? NSScreen.main
            if let screen = mouseScreen {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 140
                let y = screenFrame.maxY - 70
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        overlayWindow?.orderFront(nil)
    }

    private func showOverlayBriefly() {
        showOverlay()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = appState.status {
                appState.status = .idle
            }
            dismissOverlay()
        }
    }

    private func dismissOverlay() {
        overlayWindow?.orderOut(nil)
    }
}

// MARK: - NSSound extension

extension NSSound {
    static let tink = NSSound(named: "Tink")
    static let pop = NSSound(named: "Pop")
}

// MARK: - Overlay Container

struct OverlayContainer: View {
    @ObservedObject var appState: AppState

    var body: some View {
        RecordingOverlay(
            audioLevel: appState.audioLevel,
            status: appState.status,
            recordingStartTime: appState.recordingStartTime
        )
    }
}
