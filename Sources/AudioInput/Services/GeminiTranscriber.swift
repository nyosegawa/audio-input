import Foundation

struct GeminiTranscriber: TranscriptionService {
    let apiKey: String

    func transcribe(audioURL: URL, language: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriptionError.invalidAPIKey }

        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()

        let languageName = language == "ja" ? "Japanese" : "the detected language"

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text":
                                "Transcribe this audio in \(languageName). Return ONLY the transcribed text, nothing else. If the audio is silent, return an empty string."
                        ],
                        [
                            "inline_data": [
                                "mime_type": "audio/wav",
                                "data": base64Audio,
                            ]
                        ],
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0
            ],
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first,
            let content = firstCandidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let firstPart = parts.first,
            let text = firstPart["text"] as? String
        else {
            throw TranscriptionError.invalidResponse
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.emptyTranscription }

        return trimmed
    }
}
