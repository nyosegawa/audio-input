import Foundation

struct OpenRouterModel: Identifiable, Sendable {
    let id: String
    let name: String
    let promptPricing: String?
    let completionPricing: String?
}

@MainActor
final class OpenRouterService: ObservableObject {
    @Published var availableModels: [OpenRouterModel] = []
    @Published var isFetchingModels = false

    func fetchModels() async {
        isFetchingModels = true
        defer { isFetchingModels = false }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                NSLog("[OPENROUTER] Failed to fetch models: HTTP %d", (response as? HTTPURLResponse)?.statusCode ?? 0)
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else {
                NSLog("[OPENROUTER] Invalid response format")
                return
            }

            var models: [OpenRouterModel] = []
            for item in dataArray {
                guard let id = item["id"] as? String,
                      let name = item["name"] as? String else { continue }

                let pricing = item["pricing"] as? [String: Any]
                let promptPrice = pricing?["prompt"] as? String
                let completionPrice = pricing?["completion"] as? String

                models.append(OpenRouterModel(
                    id: id,
                    name: name,
                    promptPricing: promptPrice,
                    completionPricing: completionPrice
                ))
            }

            availableModels = models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            NSLog("[OPENROUTER] Fetched %d models", availableModels.count)
        } catch {
            NSLog("[OPENROUTER] Error fetching models: %@", error.localizedDescription)
        }
    }
}
