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
                .help("録音に使用するマイクを選択します。デバイスが切断された場合はシステムデフォルトが使用されます")
            }

            Section("音声認識") {
                Picker("プロバイダ", selection: $settings.provider) {
                    ForEach(TranscriptionProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .help("OpenAI: 高精度・低レイテンシ ($0.003/分)。Gemini: 無料枠あり・やや遅い")

                Picker("言語", selection: $settings.language) {
                    Text("日本語").tag("ja")
                    Text("English").tag("en")
                    Text("自動検出").tag("auto")
                }
                .help("言語を指定すると認識精度が向上します。多言語を混在する場合は「自動検出」を選択してください")
            }

            Section("テキスト処理") {
                Picker("整形モード", selection: $settings.textProcessingMode) {
                    ForEach(TextProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .help("「そのまま」以外を選択すると、AIが文字起こし結果を整形します。追加のAPI呼び出し（OpenAI gpt-4o-mini）が発生します")

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
                    .help("AIに送るシステムプロンプトを自由に設定できます。例:「英語に翻訳してください」「箇条書きにまとめてください」")
                }
            }

            Section("APIキー") {
                SecureField("OpenAI API Key", text: $settings.openAIKey)
                    .help("OpenAIの音声認識とテキスト整形に使用します。.envファイルでも設定可能です")
                SecureField("Gemini API Key", text: $settings.geminiKey)
                    .help("Gemini音声認識に使用します。.envファイルでも設定可能です")
            }

            Section("録音") {
                Picker("モード", selection: $settings.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .help("Push to Talk: ホットキーを押している間だけ録音。Toggle: 1回押して開始、もう1回押して停止")

                if settings.recordingMode == .toggle {
                    Toggle("無音検出で自動停止", isOn: $settings.silenceDetectionEnabled)
                        .help("録音中に無音状態が続くと自動的に停止して文字起こしを開始します")

                    if settings.silenceDetectionEnabled {
                        Picker("無音時間", selection: $settings.silenceDuration) {
                            Text("1.5秒").tag(1.5)
                            Text("2秒").tag(2.0)
                            Text("3秒").tag(3.0)
                            Text("5秒").tag(5.0)
                        }
                        .help("無音がこの秒数続くと自動停止します。背景ノイズが多い環境では長めに設定してください")
                    }
                }

                HStack {
                    Text("ホットキー")
                    Spacer()
                    Text(hotkeyDescription)
                        .foregroundColor(.secondary)
                }
                .help("現在のホットキー設定です。変更するにはアプリの再設定が必要です")
            }

            Section("一般") {
                Toggle("ログイン時に起動", isOn: $settings.launchAtLogin)
                    .help("macOS起動時にAudioInputを自動的に起動します")
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
