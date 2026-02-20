import Foundation

/// Service for fetching nearby stores from the RTL API
class RTLStoreService {
    private let program: String
    private let environment: RTLEnvironment
    private let externalChapterId: String?
    private let apiKey = "2F7ZqPuvDr0LBtjqJQpNJKWA8FqkKAbJ"

    init(program: String, environment: RTLEnvironment, externalChapterId: String?) {
        self.program = program
        self.environment = environment
        self.externalChapterId = externalChapterId
    }

    /// Fetch stores near the given coordinates
    func fetchNearbyStores(latitude: Double, longitude: Double) async throws -> [RTLStore] {
        let domain: String
        switch environment {
        case .staging:
            domain = "\(program).staging.getboon.com"
        case .production:
            domain = "\(program).prod.getboon.com"
        }

        var urlString = "https://\(domain)/api/rest/cp/stores/nearby?lat=\(latitude)&long=\(longitude)"
        if let chapterId = externalChapterId {
            urlString += "&externalChapterId=\(chapterId)"
        }

        guard let url = URL(string: urlString) else {
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
