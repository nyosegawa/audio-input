import AppKit
import SwiftUI

struct MenuBarView: View {
    var appState: AppState
    @ObservedObject var settings: AppSettings
    var onOpenSettings: () -> Void
    var onOpenHistory: () -> Void

    var body: some View {
        Text(appState.statusText)

        Divider()

        Text(settings.provider.displayName)
        Text(hotkeyDescription)

        if settings.provider.isLocal,
           case .downloading(let progress) = appState.modelDownloadState {
            Text("モデルDL中 \(Int(progress * 100))%")
        }

        if case .denied = appState.micPermission {
            Button("マイクが未許可 — 設定を開く") {
                PermissionChecker.openMicrophoneSettings()
            }
        }

        if case .denied = appState.accessibilityPermission {
            Button("アクセシビリティ未許可 — OFF→ONで再許可") {
                PermissionChecker.openAccessibilitySettings()
            }
        }

        Divider()

        if !settings.openRouterKey.isEmpty && !settings.openRouterModel.isEmpty {
            Picker("整形モード", selection: $settings.textProcessingMode) {
                ForEach(TextProcessingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        } else {
            Text("整形: 設定でAPI Key/モデルを設定")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("履歴") {
            onOpenHistory()
        }
        .keyboardShortcut("h")

        Button("設定...") {
            onOpenSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("AudioInputを終了") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var hotkeyDescription: String {
        HotkeyFormatter.description(code: settings.hotkeyCode, modifiers: settings.hotkeyModifiers)
            + " / ⌃+⇧+Space — " + settings.recordingMode.displayName
    }
}
