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

struct TextProcessor: Sendable {
    let apiKey: String

    func process(text: String, mode: TextProcessingMode, customPrompt: String? = nil) async throws -> String {
        let systemPrompt: String
        if mode == .custom {
            guard let custom = customPrompt, !custom.isEmpty else { return text }
            systemPrompt = custom
        } else {
            guard let prompt = mode.systemPrompt else { return text }
            systemPrompt = prompt
        }
        guard !apiKey.isEmpty else { return text }

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.3,
            "max_tokens": 2048,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else { return text }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else { return text }

        let processed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return processed.isEmpty ? text : processed
    }
}
