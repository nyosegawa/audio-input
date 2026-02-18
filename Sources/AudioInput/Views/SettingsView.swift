import AudioToolbox
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var appState: AppState
    @ObservedObject var whisperTranscriber: WhisperTranscriber
    @ObservedObject var openRouterService: OpenRouterService
    var onSwitchModel: (WhisperModel) -> Void
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var selectedModel: WhisperModel = .largeTurbo

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

                if settings.provider.isLocal {
                    Picker("モデル", selection: $selectedModel) {
                        ForEach(WhisperModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    modelStatusView
                }

                if settings.provider == .openAI {
                    SecureField("OpenAI API Key", text: $settings.openAIKey)
                }

                if settings.provider == .gemini {
                    SecureField("Gemini API Key", text: $settings.geminiKey)
                }

                Picker("言語", selection: $settings.language) {
                    Text("日本語").tag("ja")
                    Text("English").tag("en")
                    Text("自動検出").tag("auto")
                }
            }

            Section("テキスト処理") {
                if settings.openRouterKey.isEmpty || settings.openRouterModel.isEmpty {
                    Text("モデルを選択してAPI Keyを入力してください")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Picker("整形モード", selection: $settings.textProcessingMode) {
                    ForEach(TextProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(settings.openRouterKey.isEmpty || settings.openRouterModel.isEmpty)

                if settings.textProcessingMode == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("カスタムプロンプト")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $settings.customPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 100)
                            .border(Color.secondary.opacity(0.3))
                    }
                }

                Picker("モデル", selection: $settings.openRouterModel) {
                    Text("未選択").tag("")
                    ForEach(openRouterService.availableModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }

                SecureField("OpenRouter API Key", text: $settings.openRouterKey)
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
                        .foregroundStyle(.secondary)
                }
                .help("現在のホットキー設定です。変更するにはアプリの再設定が必要です")
            }

            Section("一般") {
                Toggle("ログイン時に起動", isOn: $settings.launchAtLogin)
                    .help("macOS起動時にAudioInputを自動的に起動します")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 580)
        .onAppear {
            inputDevices = AudioRecorder.availableInputDevices()
            selectedModel = settings.whisperModel
        }
        .onChange(of: selectedModel) {
            // Clear error/download state when user picks a different model
            if case .error = appState.modelDownloadState {
                appState.modelDownloadState = .notDownloaded
            }
        }
    }

    // MARK: - Model Status View

    @ViewBuilder
    private var modelStatusView: some View {
        let isSelectedLoaded = whisperTranscriber.loadedModel == selectedModel
        let isDownloaded = whisperTranscriber.isModelDownloaded(selectedModel)

        if case .loading = appState.modelDownloadState {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("モデルをロード中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if case .downloading(let progress) = appState.modelDownloadState {
            VStack(alignment: .leading, spacing: 4) {
                if progress > 0 {
                    HStack {
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("ダウンロード中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if isSelectedLoaded {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
                Text("使用中")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } else {
            if case .error(let msg) = appState.modelDownloadState {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 12))
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            if isDownloaded {
                Button("変更する") {
                    onSwitchModel(selectedModel)
                }
            } else {
                Button(appState.modelDownloadState.isError ? "リトライ" : "ダウンロードする") {
                    onSwitchModel(selectedModel)
                }
            }
        }
    }


    private var hotkeyDescription: String {
        HotkeyFormatter.description(code: settings.hotkeyCode, modifiers: settings.hotkeyModifiers)
    }
}
