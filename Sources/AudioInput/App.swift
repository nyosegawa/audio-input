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
    let whisperTranscriber = WhisperTranscriber()

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
        loadStreamingModelIfNeeded()
        playStartupSound()
        NSLog("[APP] Launch complete - provider: \(settings.provider.rawValue), accessibility: \(AXIsProcessTrusted()), modelLoaded: \(whisperTranscriber.isModelLoaded)")
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
            // Only prompt once; don't auto-prompt on every launch
            // since rebuilds change code signature and trigger repeated dialogs
            if !UserDefaults.standard.bool(forKey: "hasPromptedAccessibility") {
                UserDefaults.standard.set(true, forKey: "hasPromptedAccessibility")
                PermissionChecker.requestAccessibilityAccess()
            }
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
            let canStream = settings.provider.isLocal && whisperTranscriber.isModelLoaded
            NSLog("[RECORD] Streaming check - provider.isLocal: \(settings.provider.isLocal), modelLoaded: \(whisperTranscriber.isModelLoaded)")
            if canStream {
                NSLog("[STREAM] Starting streaming transcription")
                let language = settings.language
                let recorderRef = recorder
                whisperTranscriber.startStreamingTranscription(
                    audioSamplesProvider: { recorderRef.audioSamples },
                    language: language,
                    onUpdate: { [weak self] confirmed, hypothesis in
                        NSLog("[STREAM] onUpdate - confirmed: '%@', hypothesis: '%@'", confirmed, hypothesis)
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

                NSLog("[TRANSCRIBE] Result text (%d chars): %@", text.count, String(text.prefix(100)))
                NSLog("[TRANSCRIBE] Accessibility: \(AXIsProcessTrusted())")
                await textInserter.insert(text: text)
                NSLog("[TRANSCRIBE] Text insertion done")

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

    // MARK: - whisper.cpp

    func loadWhisperModelIfNeeded() {
        guard settings.provider == .local else {
            NSLog("[WHISPER] Skipping model load - provider is %@", settings.provider.rawValue)
            return
        }
        let model = settings.whisperModel
        NSLog("[WHISPER] Starting model load: %@", model.rawValue)

        Task { @MainActor in
            do {
                try await whisperTranscriber.ensureModelReady(model) { progress in
                    self.appState.modelDownloadState = .downloading(progress)
                }
                self.appState.modelDownloadState = .downloaded
                NSLog("[WHISPER] Model loaded successfully, isModelLoaded: \(self.whisperTranscriber.isModelLoaded)")
            } catch {
                self.appState.modelDownloadState = .error(error.localizedDescription)
                NSLog("[WHISPER] Model load failed: %@", error.localizedDescription)
            }
        }
    }

    func loadStreamingModelIfNeeded() {
        // No-op: whisper.cpp uses a single model for both streaming and final transcription
    }

    // MARK: - Sound

    private func playStartupSound() {
        NSSound(named: "Glass")?.play()
    }

    // MARK: - Overlay Window

    static let overlayWidth: CGFloat = 420
    private static let overlayMaxHeight: CGFloat = 200

    private func showOverlay() {
        if overlayWindow == nil {
            let initialFrame = NSRect(x: 0, y: 0, width: Self.overlayWidth, height: Self.overlayMaxHeight)
            let container = ConstraintFreeContainer(frame: initialFrame)
            container.translatesAutoresizingMaskIntoConstraints = true

            let hostingView = NSHostingView(rootView: OverlayContainer(appState: appState))
            hostingView.translatesAutoresizingMaskIntoConstraints = true
            hostingView.frame = container.bounds
            hostingView.autoresizingMask = [.width, .height]
            container.addSubview(hostingView)

            let window = ConstraintFreeWindow(
                contentRect: initialFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = container
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = true

            overlayWindow = window
        }

        // Position at top center of the screen containing the mouse pointer
        if let window = overlayWindow {
            let mouseScreen = NSScreen.screens.first(where: {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            }) ?? NSScreen.main
            if let screen = mouseScreen {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - Self.overlayWidth / 2
                let y = screenFrame.maxY - Self.overlayMaxHeight - 10
                window.setFrame(
                    NSRect(x: x, y: y, width: Self.overlayWidth, height: Self.overlayMaxHeight),
                    display: true
                )
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

// MARK: - Constraint-Free Window & Container
//
// On macOS 26, NSHostingView's internal child views trigger constraint
// re-invalidation during the display cycle commit phase, causing
// _updateConstraintsForSubtreeIfNeededCollectingViewsWithInvalidBaselines:
// to throw an exception (SIGABRT).
//
// NSWindow.updateConstraintsIfNeeded() initiates the constraint tree walk
// that reaches into NSHostingView's internal views via private _-prefixed
// methods. Overriding the view-level updateConstraintsForSubtreeIfNeeded
// alone is insufficient because AppKit bypasses it for child views.
//
// The fix: block at the WINDOW level so the walk never starts.
// SwiftUI rendering is unaffected — it uses its own CADisplayLink-driven
// view graph update mechanism, not Auto Layout constraints.
//
// All overrides are nonisolated to prevent Swift 6 from generating
// @objc thunks with MainActor isolation checks. AppKit calls these from
// the display cycle which runs on the main thread but lacks a Swift Task
// context, causing swift_task_isMainExecutorImpl to crash.

final class ConstraintFreeWindow: NSWindow {
    nonisolated override func updateConstraintsIfNeeded() { }
}

final class ConstraintFreeContainer: NSView {
    nonisolated override var needsUpdateConstraints: Bool {
        get { false }
        set { }
    }
    nonisolated override func updateConstraints() { }
    nonisolated override func updateConstraintsForSubtreeIfNeeded() { }
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
        .frame(width: AppDelegate.overlayWidth, alignment: .topLeading)
    }
}
