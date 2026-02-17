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
        case .invalidAPIKey:
            return "APIキーが未設定です"
        case .networkError(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    return "接続がタイムアウトしました"
                case .notConnectedToInternet:
                    return "インターネットに接続されていません"
                case .networkConnectionLost:
                    return "ネットワーク接続が切断されました"
                case .cannotConnectToHost:
                    return "サーバーに接続できません"
                case .dnsLookupFailed:
                    return "DNS解決に失敗しました"
                default:
                    return "ネットワークエラー: \(urlError.localizedDescription)"
                }
            }
            return "ネットワークエラー: \(error.localizedDescription)"
        case .apiError(let message):
            if message.contains("HTTP 429") {
                return "APIレート制限に達しました。しばらく待ってから再試行してください"
            }
            if message.contains("HTTP 401") || message.contains("HTTP 403") {
                return "APIキーが無効です。設定を確認してください"
            }
            if message.contains("HTTP 5") {
                return "サーバーエラーが発生しました。しばらく待ってから再試行してください"
            }
            return "APIエラー: \(message)"
        case .invalidResponse:
            return "不正なレスポンス"
        case .emptyTranscription:
            return "音声が検出されませんでした"
        }
    }
}
