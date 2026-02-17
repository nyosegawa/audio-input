import Foundation

struct OpenAITranscriber: TranscriptionService {
    let apiKey: String

    func transcribe(audioURL: URL, language: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriptionError.invalidAPIKey }

        let audioData = try Data(contentsOf: audioURL)

        var form = MultipartFormData()
        form.addFile(
            name: "file", filename: "audio.wav", mimeType: "audio/wav", data: audioData)
        form.addField(name: "model", value: "gpt-4o-mini-transcribe")
        form.addField(name: "language", value: language)
        form.addField(name: "response_format", value: "json")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.build()
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

        struct Response: Decodable {
            let text: String
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TranscriptionError.invalidResponse
        }

        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscription }

        return text
    }
}
