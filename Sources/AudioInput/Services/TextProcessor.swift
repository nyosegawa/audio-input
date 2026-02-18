import Foundation

enum TextProcessingMode: String, CaseIterable, Sendable {
    case none = "none"
    case cleanup = "cleanup"
    case formal = "formal"
    case casual = "casual"
    case email = "email"
    case code = "code"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .none: "そのまま"
        case .cleanup: "整形（フィラー除去）"
        case .formal: "丁寧語"
        case .casual: "カジュアル"
        case .email: "メール文"
        case .code: "コードコメント"
        case .custom: "カスタム"
        }
    }

    var systemPrompt: String? {
        switch self {
        case .none: nil
        case .cleanup:
            """
            以下の音声認識テキストを整形してください。
            - 「えーと」「あの」「まあ」などのフィラーワードを除去
            - 適切な句読点を追加
            - 繰り返しや言い直しを整理
            - 内容は変更しない
            整形後のテキストのみを返してください。
            """
        case .formal:
            """
            以下の音声認識テキストを丁寧な日本語に整形してください。
            - フィラーワードを除去
            - ですます調に統一
            - 適切な句読点を追加
            整形後のテキストのみを返してください。
            """
        case .casual:
            """
            以下の音声認識テキストをカジュアルな日本語に整形してください。
            - フィラーワードを除去
            - 自然な口語表現に
            - 適切な句読点を追加
            整形後のテキストのみを返してください。
            """
        case .email:
            """
            以下の音声認識テキストをメール文として整形してください。
            - フィラーワードを除去
            - ビジネスメールにふさわしい丁寧な文体
            - 適切な段落分け
            整形後のテキストのみを返してください。
            """
        case .code:
            """
            以下の音声認識テキストをコードコメントとして整形してください。
            - プログラミングの文脈を考慮
            - 簡潔で明確な表現
            - 技術用語は英語のまま
            整形後のテキストのみを返してください。
            """
        case .custom: nil
        }
    }
}

enum TextProcessingError: Error, LocalizedError {
    case networkError(Error)
    case openRouterError(code: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            "テキスト整形ネットワークエラー: \(error.localizedDescription)"
        case .openRouterError(let code, let message):
            "テキスト整形APIエラー (HTTP \(code)): \(message)"
        case .invalidResponse:
            "テキスト整形: 不正なレスポンス"
        }
    }

    /// User-facing short message for overlay display
    var userMessage: String {
        switch self {
        case .networkError:
            "整形失敗: ネットワークエラー"
        case .openRouterError(let code, let raw):
            switch code {
            case 400:
                "整形失敗: リクエストが不正です"
            case 401:
                "整形失敗: APIキーが無効です。設定を確認してください"
            case 402:
                "整形失敗: OpenRouterのクレジットが不足しています"
            case 403:
                "整形失敗: コンテンツがモデレーションに引っかかりました"
            case 404:
                if raw.contains("data policy") {
                    "整形失敗: OpenRouterのPrivacy設定を確認してください"
                } else {
                    "整形失敗: モデルが見つかりません"
                }
            case 408:
                "整形失敗: タイムアウト。再試行してください"
            case 429:
                "整形失敗: レート制限中。しばらく待ってください"
            case 502:
                "整形失敗: モデルが応答不能です。別のモデルを試してください"
            case 503:
                "整形失敗: 利用可能なプロバイダがありません"
            default:
                "整形失敗: HTTP \(code)"
            }
        case .invalidResponse:
            "整形失敗: 不正なレスポンス"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkError:
            true
        case .openRouterError(let code, _):
            // 429 rate limit, 408 timeout, 502/503 server issues are retryable
            [408, 429, 502, 503].contains(code)
        case .invalidResponse:
            false
        }
    }
}

struct TextProcessor: Sendable {
    let apiKey: String
    let model: String

    func process(text: String, mode: TextProcessingMode, customPrompt: String? = nil) async throws -> String {
        let systemPrompt: String
        if mode == .custom {
            guard let custom = customPrompt, !custom.isEmpty else { return text }
            systemPrompt = """
            以下の指示に従って、ユーザーの音声認識テキストを変換してください。
            変換後のテキストのみを返してください。説明・補足・挨拶は一切不要です。

            指示: \(custom)
            """
        } else {
            guard let prompt = mode.systemPrompt else { return text }
            systemPrompt = prompt
        }
        guard !apiKey.isEmpty, !model.isEmpty else {
            AppLogger.log("[PROCESS] Skipped: apiKey.isEmpty=\(apiKey.isEmpty), model.isEmpty=\(model.isEmpty)")
            return text
        }

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.3,
            "max_tokens": 2048,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AudioInput", forHTTPHeaderField: "X-Title")
        request.httpBody = jsonData
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TextProcessingError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TextProcessingError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = Self.parseOpenRouterError(data: data, statusCode: httpResponse.statusCode)
            throw TextProcessingError.openRouterError(code: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw TextProcessingError.invalidResponse
        }

        let processed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return processed.isEmpty ? text : processed
    }

    /// Parse OpenRouter error JSON to extract the message
    private static func parseOpenRouterError(data: Data, statusCode: Int) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }

        // Extract metadata.raw for upstream provider errors (e.g., 429 rate limit details)
        if let metadata = error["metadata"] as? [String: Any],
           let raw = metadata["raw"] as? String {
            return raw
        }

        return error["message"] as? String ?? "Unknown error"
    }
}
