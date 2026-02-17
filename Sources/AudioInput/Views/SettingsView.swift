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
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 350)
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
