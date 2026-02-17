import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("音声認識") {
                Picker("プロバイダ", selection: $settings.provider) {
                    ForEach(TranscriptionProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                Picker("言語", selection: $settings.language) {
                    Text("日本語").tag("ja")
                    Text("English").tag("en")
                    Text("自動検出").tag("auto")
                }
            }

            Section("テキスト処理") {
                Picker("整形モード", selection: $settings.textProcessingMode) {
                    ForEach(TextProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("APIキー") {
                SecureField("OpenAI API Key", text: $settings.openAIKey)
                SecureField("Gemini API Key", text: $settings.geminiKey)
            }

            Section("録音") {
                Picker("モード", selection: $settings.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                HStack {
                    Text("ホットキー")
                    Spacer()
                    Text(hotkeyDescription)
                        .foregroundColor(.secondary)
                }
            }

            Section("一般") {
                Toggle("ログイン時に起動", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 450)
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

        return parts.joined(separator: "+")
    }
}
