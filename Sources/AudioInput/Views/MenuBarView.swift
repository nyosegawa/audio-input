import Carbon
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    @State private var showSettings = false
    @State private var showHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.statusText)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Provider info
            HStack {
                Image(systemName: "brain")
                    .font(.system(size: 11))
                Text(settings.provider.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Processing mode
            HStack {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 11))
                Text(settings.textProcessingMode.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Hotkey info
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 11))
                Text(hotkeyDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Permission warnings
            if case .denied = appState.micPermission {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("マイクが許可されていません")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            if case .denied = appState.accessibilityPermission {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("アクセシビリティが未許可")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Divider()

            // Quick mode toggle
            Menu("整形モード") {
                ForEach(TextProcessingMode.allCases, id: \.self) { mode in
                    Button {
                        settings.textProcessingMode = mode
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if settings.textProcessingMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button("履歴 (\(appState.history.count))") {
                showHistory.toggle()
            }
            .keyboardShortcut("h")
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button("設定...") {
                showSettings.toggle()
            }
            .keyboardShortcut(",")
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(records: appState.history)
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: .green
        case .recording: .red
        case .transcribing, .processing: .orange
        case .success: .green
        case .error: .red
        }
    }

    private var hotkeyDescription: String {
        var parts: [String] = []
        let mods = settings.hotkeyModifiers
        if mods & UInt32(optionKey) != 0 { parts.append("⌥") }
        if mods & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if mods & UInt32(controlKey) != 0 { parts.append("⌃") }
        if mods & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if settings.hotkeyCode == KeyCodes.space {
            parts.append("Space")
        } else {
            parts.append("Key(\(settings.hotkeyCode))")
        }
        return parts.joined(separator: "+") + " で" + settings.recordingMode.displayName
    }
}
