import AudioToolbox
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var inputDevices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section("入力デバイス") {
                Picker("マイク", selection: $settings.selectedInputDeviceID) {
                    Text("システムデフォルト").tag(nil as AudioDeviceID?)
                    ForEach(inputDevices) { device in
                        Text(device.name + (device.isDefault ? " (デフォルト)" : ""))
                            .tag(device.id as AudioDeviceID?)
                    }
                }
            }

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

                if settings.textProcessingMode == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("カスタムプロンプト")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $settings.customPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 100)
                            .border(Color.secondary.opacity(0.3))
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

                if settings.recordingMode == .toggle {
                    Toggle("無音検出で自動停止", isOn: $settings.silenceDetectionEnabled)

                    if settings.silenceDetectionEnabled {
                        Picker("無音時間", selection: $settings.silenceDuration) {
                            Text("1.5秒").tag(1.5)
                            Text("2秒").tag(2.0)
                            Text("3秒").tag(3.0)
                            Text("5秒").tag(5.0)
                        }
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
        .frame(width: 420, height: dynamicHeight)
        .onAppear {
            inputDevices = AudioRecorder.availableInputDevices()
        }
    }

    private var dynamicHeight: CGFloat {
        var height: CGFloat = 500
        if settings.textProcessingMode == .custom { height += 120 }
        if settings.recordingMode == .toggle { height += 30 }
        if settings.recordingMode == .toggle && settings.silenceDetectionEnabled { height += 30 }
        return height
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
