import Foundation

protocol TranscriptionService: Sendable {
    func transcribe(audioURL: URL, language: String) async throws -> String
}

enum TranscriptionError: Error, LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case apiError(String)
    case invalidResponse
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: "APIキーが未設定です"
        case .networkError(let error): "ネットワークエラー: \(error.localizedDescription)"
        case .apiError(let message): "APIエラー: \(message)"
        case .invalidResponse: "不正なレスポンス"
        case .emptyTranscription: "音声が検出されませんでした"
        }
    }
}
