import Foundation

/// Fetches locations with hyperlocal offers from the RTL API.
class RTLHyperlocalOffersService {
    private let baseURL: URL
    private let externalChapterId: String?
    private let sessionCookieHeader: (URL) async -> String?

    init(
        baseURL: URL,
        externalChapterId: String?,
        sessionCookieHeader: @escaping (URL) async -> String?
    ) {
        self.baseURL = baseURL
        self.externalChapterId = externalChapterId
        self.sessionCookieHeader = sessionCookieHeader
    }

    /// Fetch locations with offers near the given coordinates.
    func fetchHyperlocalOffers(latitude: Double, longitude: Double) async throws -> [RTLStore] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RTLHyperlocalOffersServiceError.invalidURL
        }
        components.path = "/api/rest/hyperlocal-offers"
        components.fragment = nil
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "long", value: String(longitude))
        ]
        if let chapterId = externalChapterId {
            components.queryItems?.append(URLQueryItem(name: "externalChapterId", value: chapterId))
        }

        guard let url = components.url else {
            throw RTLHyperlocalOffersServiceError.invalidURL
        }

        guard let cookieHeader = await sessionCookieHeader(url), !cookieHeader.isEmpty else {
            RTLLog.warn(.store, "Cannot fetch hyperlocal offers without a signed-in session")
            throw RTLHyperlocalOffersServiceError.unauthenticated
        }

        var request = URLRequest(url: url)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        RTLLog.debug(.store, "Fetching hyperlocal offers from: \(RTLLog.url(url.absoluteString))")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RTLHyperlocalOffersServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            RTLLog.debug(.store, "Hyperlocal offers API returned status: \(httpResponse.statusCode)")
            throw RTLHyperlocalOffersServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let offers = try JSONDecoder().decode([RTLStore].self, from: data)
        RTLLog.debug(.store, "Fetched \(offers.count) hyperlocal offers")
        return offers
    }
}

enum RTLHyperlocalOffersServiceError: Error {
    case invalidURL
    case invalidResponse
    case unauthenticated
    case httpError(statusCode: Int)
}
