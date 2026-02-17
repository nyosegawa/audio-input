import AppKit
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
    private var recordingURL: URL?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerHotkey()
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        dismissOverlay()
    }

    @MainActor
    private func registerHotkey() {
        hotkeyManager.register(
            keyCode: settings.hotkeyCode,
            modifiers: settings.hotkeyModifiers,
            onKeyDown: { [weak self] in
                guard let self = self else { return }
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

    @MainActor
    private func startRecording() {
        guard !appState.isRecording else { return }

        do {
            let url = try recorder.startRecording()
            recordingURL = url
            appState.status = .recording
            showOverlay()
        } catch {
            appState.status = .error("録音開始失敗: \(error.localizedDescription)")
            showOverlayBriefly()
        }
    }

    @MainActor
    private func stopRecordingAndTranscribe() {
        guard appState.isRecording else { return }

        guard let result = recorder.stopRecording() else {
            appState.status = .error("録音データなし")
            showOverlayBriefly()
            return
        }

        // Skip very short recordings (< 0.3 seconds)
        if result.duration < 0.3 {
            recorder.cleanup(url: result.url)
            appState.status = .idle
            dismissOverlay()
            return
        }

        appState.status = .transcribing
        showOverlay()

        let transcriber = createTranscriber()
        let language = settings.language
        let provider = settings.provider

        Task { @MainActor in
            do {
                let text = try await transcriber.transcribe(
                    audioURL: result.url, language: language)

                let record = TranscriptionRecord(
                    text: text,
                    date: Date(),
                    duration: result.duration,
                    provider: provider
                )
                appState.addRecord(record)

                await textInserter.insert(text: text)

                appState.status = .idle
                dismissOverlay()
            } catch {
                let errorMsg =
                    (error as? TranscriptionError)?.errorDescription
                    ?? error.localizedDescription
                appState.status = .error(errorMsg)
                showOverlayBriefly()
            }

            recorder.cleanup(url: result.url)
        }
    }

    @MainActor
    private func createTranscriber() -> TranscriptionService {
        switch settings.provider {
        case .openAI:
            OpenAITranscriber(apiKey: settings.openAIKey)
        case .gemini:
            GeminiTranscriber(apiKey: settings.geminiKey)
        }
    }

    // MARK: - Overlay Window

    @MainActor
    private func showOverlay() {
        if overlayWindow == nil {
            let hostingView = NSHostingView(
                rootView: OverlayContainer(appState: appState))

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 50),
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

            // Position at top center of main screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 130
                let y = screenFrame.maxY - 70
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            overlayWindow = window
        }

        overlayWindow?.orderFront(nil)
    }

    @MainActor
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

    @MainActor
    private func dismissOverlay() {
        overlayWindow?.orderOut(nil)
    }
}

struct OverlayContainer: View {
    @ObservedObject var appState: AppState

    var body: some View {
        RecordingOverlay(audioLevel: appState.audioLevel, status: appState.status)
    }
}
