import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var appState: AppState
    var onComplete: () -> Void

    @State private var step = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Spacer()

            // Content
            Group {
                switch step {
                case 0: welcomeStep
                case 1: microphoneStep
                case 2: accessibilityStep
                case 3: providerStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            Spacer()

            // Navigation
            HStack {
                if step > 0 {
                    Button("戻る") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button("次へ") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("始める") {
                        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("AudioInput へようこそ")
                .font(.title2.bold())
            Text("AIを使った音声入力ツールです。\nホットキーで録音し、文字起こしした結果を\nアクティブなアプリに自動入力します。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("マイクへのアクセス")
                .font(.title3.bold())

            permissionRow(
                granted: appState.micPermission == .granted,
                label: "マイク",
                action: {
                    if case .notDetermined = appState.micPermission {
                        Task {
                            let granted = await PermissionChecker.requestMicrophoneAccess()
                            appState.micPermission = granted ? .granted : .denied
                        }
                    } else {
                        PermissionChecker.openMicrophoneSettings()
                    }
                }
            )

            Text("音声の録音にマイクへのアクセスが必要です。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("アクセシビリティ")
                .font(.title3.bold())

            permissionRow(
                granted: appState.accessibilityPermission == .granted,
                label: "アクセシビリティ",
                action: { PermissionChecker.requestAccessibilityAccess() }
            )

            Text("テキストの貼り付け（Cmd+V）にアクセシビリティ権限が必要です。\nシステム設定でAudioInputを許可してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var providerStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("音声認識の設定")
                .font(.title3.bold())

            Picker("プロバイダ", selection: $settings.provider) {
                ForEach(TranscriptionProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Group {
                if settings.provider.isLocal {
                    Text("ローカルモデルを使用します。初回はモデルのダウンロードが必要です（約500MB）。")
                } else if settings.provider == .openAI {
                    SecureField("OpenAI API Key", text: $settings.openAIKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Gemini API Key", text: $settings.geminiKey)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("ホットキー: \(HotkeyFormatter.description(code: settings.hotkeyCode, modifiers: settings.hotkeyModifiers))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func permissionRow(granted: Bool, label: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .red)
            Text(label)
            Spacer()
            if !granted {
                Button("許可する") { action() }
                    .buttonStyle(.bordered)
            } else {
                Text("許可済み")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
