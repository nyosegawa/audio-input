import AppKit
import Combine
import SwiftUI

@main
struct AudioInputApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appDelegate.appState, settings: appDelegate.settings, whisperTranscriber: appDelegate.whisperTranscriber)
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
    let whisperTranscriber = WhisperKitTranscriber()

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
        loadWhisperModelIfNeeded()
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
                NSLog("[HOTKEY] keyDown - status: \(self.appState.status), isRecording: \(self.appState.isRecording), mode: \(self.settings.recordingMode)")
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
                NSLog("[HOTKEY] keyUp - status: \(self.appState.status), isRecording: \(self.appState.isRecording), mode: \(self.settings.recordingMode)")
                if self.settings.recordingMode == .pushToTalk && self.appState.isRecording {
                    // Debounce: if keyUp fires within 0.5s of recording start,
                    // ignore it (likely spurious from system key handling).
                    // User can press again to stop (toggle fallback).
                    if let start = self.appState.recordingStartTime,
                       Date().timeIntervalSince(start) < 0.5 {
                        NSLog("[HOTKEY] keyUp ignored - only %.2fs since recording start, press again to stop", Date().timeIntervalSince(start))
                        return
                    }
                    self.stopRecordingAndTranscribe()
                }
            }
        )

        // Secondary hotkey: Ctrl+Shift+Space (guaranteed no conflict)
        hotkeyManager.registerAdditional(
            keyCode: KeyCodes.space,
            modifiers: HotkeyModifiers.control.rawValue | HotkeyModifiers.shift.rawValue
        )
    }

    // MARK: - Recording

    private func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        whisperTranscriber.stopStreamingTranscription()
        appState.confirmedStreamingText = ""
        appState.hypothesisStreamingText = ""
        if let url = lastRecordingURL {
            recorder.cleanup(url: url)
            lastRecordingURL = nil
        }
        appState.status = .error("キャンセルしました")
        showOverlayBriefly()
    }

    private func startRecording() {
        NSLog("[RECORD] startRecording called, isRecording: \(appState.isRecording)")
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
            appState.confirmedStreamingText = ""
            appState.hypothesisStreamingText = ""
            NSSound.tink?.play()
            showOverlay()

            // Start streaming transcription for local model
            if settings.provider.isLocal && whisperTranscriber.isModelLoaded {
                let language = settings.language
                let recorderRef = recorder
                whisperTranscriber.startStreamingTranscription(
                    audioSamplesProvider: { recorderRef.audioSamples },
                    language: language,
                    onUpdate: { [weak self] confirmed, hypothesis in
                        self?.appState.confirmedStreamingText = confirmed
                        self?.appState.hypothesisStreamingText = hypothesis
                    }
                )
            }
        } catch {
            appState.status = .error("録音開始失敗: \(error.localizedDescription)")
            showOverlayBriefly()
        }
    }

    private func stopRecordingAndTranscribe() {
        NSLog("[RECORD] stopRecordingAndTranscribe called, isRecording: \(appState.isRecording)")
        guard appState.isRecording else { return }

        appState.recordingStartTime = nil
        whisperTranscriber.stopStreamingTranscription()

        guard let result = recorder.stopRecording() else {
            appState.status = .error("録音データなし")
            appState.confirmedStreamingText = ""
            appState.hypothesisStreamingText = ""
            showOverlayBriefly()
            return
        }

        lastRecordingURL = result.url

        NSSound.pop?.play()

        // Skip very short recordings (< 0.3 seconds)
        if result.duration < 0.3 {
            recorder.cleanup(url: result.url)
            appState.status = .error("録音が短すぎます")
            appState.confirmedStreamingText = ""
            appState.hypothesisStreamingText = ""
            showOverlayBriefly()
            return
        }

        appState.status = .transcribing

        let provider = settings.provider
        let language = settings.language
        let processingMode = settings.textProcessingMode
        let customPrompt = settings.customPrompt
        let processorKey = settings.openAIKey
        let useLocal = provider.isLocal && whisperTranscriber.isModelLoaded

        transcriptionTask = Task { @MainActor in
            do {
                try Task.checkCancellation()
                var text: String

                if useLocal {
                    text = try await whisperTranscriber.transcribe(
                        audioURL: result.url, language: language)
                } else {
                    let transcriber = createTranscriber()
                    text = try await RetryHelper.withRetry {
                        try await transcriber.transcribe(
                            audioURL: result.url, language: language)
                    }
                }

                appState.confirmedStreamingText = ""
                appState.hypothesisStreamingText = ""

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
                appState.confirmedStreamingText = ""
                appState.hypothesisStreamingText = ""
                showOverlayBriefly()
            }

            recorder.cleanup(url: result.url)
            lastRecordingURL = nil
            transcriptionTask = nil
        }
    }

    private func createTranscriber() -> TranscriptionService {
        switch settings.provider {
        case .local:
            // Local transcription is handled directly via whisperTranscriber
            // Fallback to OpenAI if called through this path
            OpenAITranscriber(apiKey: settings.openAIKey)
        case .openAI:
            OpenAITranscriber(apiKey: settings.openAIKey)
        case .gemini:
            GeminiTranscriber(apiKey: settings.geminiKey)
        }
    }

    // MARK: - WhisperKit

    func loadWhisperModelIfNeeded() {
        guard settings.provider == .local else { return }
        let model = settings.whisperModel

        Task { @MainActor in
            do {
                try await whisperTranscriber.ensureModelReady(model) { progress in
                    self.appState.modelDownloadState = .downloading(progress)
                }
                self.appState.modelDownloadState = .downloaded
            } catch {
                self.appState.modelDownloadState = .error(error.localizedDescription)
            }
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
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 80),
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
                let x = screenFrame.midX - 190
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
                let x = screenFrame.midX - 190
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
            recordingStartTime: appState.recordingStartTime,
            confirmedStreamingText: appState.confirmedStreamingText,
            hypothesisStreamingText: appState.hypothesisStreamingText
        )
    }
}
