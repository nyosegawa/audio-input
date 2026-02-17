import Foundation

enum TranscriptionProvider: String, CaseIterable, Sendable {
    case openAI = "openai"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .openAI: "OpenAI (gpt-4o-mini-transcribe)"
        case .gemini: "Gemini 2.0 Flash"
        }
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

    private init() {
        self.openAIKey = UserDefaults.standard.string(forKey: "openAIKey") ?? ""
        self.geminiKey = UserDefaults.standard.string(forKey: "geminiKey") ?? ""
        self.provider = TranscriptionProvider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .openAI
        self.language = UserDefaults.standard.string(forKey: "language") ?? "ja"
        self.recordingMode = RecordingMode(rawValue: UserDefaults.standard.string(forKey: "recordingMode") ?? "") ?? .pushToTalk
        self.hotkeyCode = UInt32(UserDefaults.standard.integer(forKey: "hotkeyCode"))
        self.hotkeyModifiers = UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))

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
