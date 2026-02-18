import AudioToolbox
import Foundation

enum TranscriptionProvider: String, CaseIterable, Codable, Sendable {
    case local = "local"
    case openAI = "openai"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .local: "ローカル (whisper.cpp)"
        case .openAI: "OpenAI (gpt-4o-mini-transcribe)"
        case .gemini: "Gemini 2.5 Flash"
        }
    }

    var isLocal: Bool {
        self == .local
    }
}

enum WhisperModel: String, CaseIterable, Sendable {
    case tiny = "ggml-tiny-q5_1"
    case base = "ggml-base"
    case small = "ggml-small-q5_1"
    case largeTurbo = "ggml-large-v3-turbo-q5_0"

    var displayName: String {
        switch self {
        case .tiny: "Tiny Q5 (~32MB, 高速・低精度)"
        case .base: "Base (~148MB, バランス)"
        case .small: "Small Q5 (~190MB, 高精度)"
        case .largeTurbo: "Large v3 Turbo Q5 (~574MB, 最高精度)"
        }
    }

    var filename: String { rawValue + ".bin" }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
}

enum RecordingMode: String, CaseIterable, Sendable {
    case pushToTalk = "push_to_talk"
    case toggle = "toggle"

    var displayName: String {
        switch self {
        case .pushToTalk: "Push to Talk"
        case .toggle: "Toggle"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var openAIKey: String {
        didSet { UserDefaults.standard.set(openAIKey, forKey: "openAIKey") }
    }
    @Published var geminiKey: String {
        didSet { UserDefaults.standard.set(geminiKey, forKey: "geminiKey") }
    }
    @Published var provider: TranscriptionProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "provider") }
    }
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var recordingMode: RecordingMode {
        didSet { UserDefaults.standard.set(recordingMode.rawValue, forKey: "recordingMode") }
    }
    @Published var hotkeyCode: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyCode, forKey: "hotkeyCode") }
    }
    @Published var hotkeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    @Published var textProcessingMode: TextProcessingMode {
        didSet { UserDefaults.standard.set(textProcessingMode.rawValue, forKey: "textProcessingMode") }
    }
    @Published var customPrompt: String {
        didSet { UserDefaults.standard.set(customPrompt, forKey: "customPrompt") }
    }
    @Published var selectedInputDeviceID: AudioDeviceID? {
        didSet {
            if let id = selectedInputDeviceID {
                UserDefaults.standard.set(Int(id), forKey: "selectedInputDeviceID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedInputDeviceID")
            }
        }
    }
    @Published var silenceDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(silenceDetectionEnabled, forKey: "silenceDetectionEnabled") }
    }
    @Published var silenceDuration: Double {
        didSet { UserDefaults.standard.set(silenceDuration, forKey: "silenceDuration") }
    }
    @Published var silenceThreshold: Float {
        didSet { UserDefaults.standard.set(silenceThreshold, forKey: "silenceThreshold") }
    }
    @Published var whisperModel: WhisperModel {
        didSet { UserDefaults.standard.set(whisperModel.rawValue, forKey: "whisperModel") }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    private init() {
        self.openAIKey = UserDefaults.standard.string(forKey: "openAIKey") ?? ""
        self.geminiKey = UserDefaults.standard.string(forKey: "geminiKey") ?? ""
        self.provider = TranscriptionProvider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .local
        self.language = UserDefaults.standard.string(forKey: "language") ?? "ja"
        self.recordingMode = RecordingMode(rawValue: UserDefaults.standard.string(forKey: "recordingMode") ?? "") ?? .pushToTalk
        self.hotkeyCode = UInt32(UserDefaults.standard.integer(forKey: "hotkeyCode"))
        self.hotkeyModifiers = UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
        self.textProcessingMode = TextProcessingMode(rawValue: UserDefaults.standard.string(forKey: "textProcessingMode") ?? "") ?? .none
        self.customPrompt = UserDefaults.standard.string(forKey: "customPrompt") ?? ""
        let storedDeviceID = UserDefaults.standard.integer(forKey: "selectedInputDeviceID")
        self.selectedInputDeviceID = storedDeviceID > 0 ? AudioDeviceID(storedDeviceID) : nil
        self.silenceDetectionEnabled = UserDefaults.standard.bool(forKey: "silenceDetectionEnabled")
        let storedSilenceDuration = UserDefaults.standard.double(forKey: "silenceDuration")
        self.silenceDuration = storedSilenceDuration > 0 ? storedSilenceDuration : 2.0
        let storedSilenceThreshold = UserDefaults.standard.float(forKey: "silenceThreshold")
        self.silenceThreshold = storedSilenceThreshold > 0 ? storedSilenceThreshold : 0.01
        self.whisperModel = WhisperModel(rawValue: UserDefaults.standard.string(forKey: "whisperModel") ?? "") ?? .largeTurbo
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")

        // Default hotkey: Option+Space
        if hotkeyCode == 0 && hotkeyModifiers == 0 {
            hotkeyCode = KeyCodes.space
            hotkeyModifiers = HotkeyModifiers.option.rawValue
        }

        loadFromEnvFile()
    }

    private func loadFromEnvFile() {
        let envPaths = [
            FileManager.default.currentDirectoryPath + "/.env",
            Bundle.main.bundlePath + "/Contents/MacOS/.env",
            Bundle.main.bundlePath + "/.env",
        ]
        for path in envPaths {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "OPENAI_API_KEY":
                        if openAIKey.isEmpty { openAIKey = value }
                    case "GEMINI_API_KEY":
                        if geminiKey.isEmpty { geminiKey = value }
                    default:
                        break
                    }
                }
                break
            }
        }
    }
}
