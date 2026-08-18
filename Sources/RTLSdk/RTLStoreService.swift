import Foundation

/// Service for fetching nearby stores from the RTL API
class RTLStoreService {
    private let baseURL: URL
    private let externalChapterId: String?
    private let apiKey = "2F7ZqPuvDr0LBtjqJQpNJKWA8FqkKAbJ"

    init(baseURL: URL, externalChapterId: String?) {
        self.baseURL = baseURL
        self.externalChapterId = externalChapterId
    }

    /// Fetch stores near the given coordinates
    func fetchNearbyStores(latitude: Double, longitude: Double) async throws -> [RTLStore] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RTLStoreServiceError.invalidURL
        }
        components.path = "/api/rest/cp/stores/nearby"
        components.fragment = nil
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "long", value: String(longitude))
        ]
        if let chapterId = externalChapterId {
            components.queryItems?.append(URLQueryItem(name: "externalChapterId", value: chapterId))
        }

        guard let url = components.url else {
            throw RTLStoreServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-affina-secret-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        print("[RTLSdk] Fetching nearby stores from: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RTLStoreServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            print("[RTLSdk] Store API returned status: \(httpResponse.statusCode)")
            throw RTLStoreServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let stores = try JSONDecoder().decode([RTLStore].self, from: data)
        print("[RTLSdk] Fetched \(stores.count) nearby stores")
        return stores
    }
}

enum RTLStoreServiceError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
}
