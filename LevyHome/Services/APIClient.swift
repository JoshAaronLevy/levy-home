import Foundation

final class APIClient {
    private enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    func fetchRecentEvents(limit: Int? = nil) async throws -> EventsResponse {
        let queryItems = limit.map { [URLQueryItem(name: "limit", value: String($0))] } ?? []
        return try await send(path: "/api/events", queryItems: queryItems)
    }

    func fetchHomeOverview() async throws -> HomeOverviewResponse {
        try await send(path: "/api/home/overview")
    }

    func fetchQuickActions() async throws -> QuickActionsResponse {
        try await send(path: "/api/home/actions")
    }

    func performQuickAction(_ request: QuickActionRequest) async throws -> QuickActionResponse {
        try await send(path: "/api/home/actions", method: .post, body: request)
    }

    func fetchNotificationPreferences() async throws -> NotificationPreferencesResponse {
        try await send(path: "/api/notification-preferences")
    }

    func updateNotificationPreferences(
        _ request: NotificationPreferencesUpdateRequest
    ) async throws -> NotificationPreferencesResponse {
        try await send(path: "/api/notification-preferences", method: .put, body: request)
    }

    func registerDevice(_ request: RegisterDeviceRequest) async throws -> RegisterDeviceResponse {
        try await send(path: "/api/devices/register", method: .post, body: request)
    }

    func sendTestPush(_ request: TestPushRequest? = nil) async throws -> TestPushResponse {
        if let request {
            return try await send(path: "/api/debug/send-test-push", method: .post, body: request)
        }

        return try await send(path: "/api/debug/send-test-push", method: .post)
    }

    func fetchHealth() async throws -> HealthResponse {
        try await send(path: "/health")
    }

    private func send<Response: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(path: path, method: method, queryItems: queryItems, bodyData: nil)
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        let bodyData: Data

        do {
            bodyData = try encoder.encode(body)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }

        return try await send(path: path, method: method, queryItems: queryItems, bodyData: bodyData)
    }

    private func send<Response: Decodable>(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem],
        bodyData: Data?
    ) async throws -> Response {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport("The API returned a non-HTTP response.")
        }

        guard 200...299 ~= httpResponse.statusCode else {
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data),
               !errorResponse.error.isEmpty {
                throw APIError.server(statusCode: httpResponse.statusCode, message: errorResponse.error)
            }

            throw APIError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            components.host != nil
        else {
            throw APIError.invalidBaseURL(baseURL.absoluteString)
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let combinedPath = [basePath, requestPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        components.path = "/\(combinedPath)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw APIError.invalidURL(path: path)
        }

        return url
    }
}
