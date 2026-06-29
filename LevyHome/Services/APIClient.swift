import Foundation

final class APIClient {
    private enum HTTPMethod: String {
        case get = "GET"
        case delete = "DELETE"
        case patch = "PATCH"
        case post = "POST"
        case put = "PUT"
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let appLogStore: AppLogStore?

    init(
        baseURL: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        appLogStore: AppLogStore? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
        self.appLogStore = appLogStore
    }

    func fetchRecentEvents(limit: Int? = nil, start: Date? = nil, end: Date? = nil) async throws -> EventsResponse {
        var queryItems: [URLQueryItem] = []

        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }

        if let start {
            queryItems.append(URLQueryItem(name: "start", value: Self.iso8601Formatter.string(from: start)))
        }

        if let end {
            queryItems.append(URLQueryItem(name: "end", value: Self.iso8601Formatter.string(from: end)))
        }

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

    func fetchUsers() async throws -> UsersResponse {
        try await send(path: "/api/users")
    }

    func fetchToDoLocations() async throws -> ToDoLocationsResponse {
        try await send(path: "/api/todo/locations")
    }

    func createToDoLocation(_ request: CreateToDoLocationRequest) async throws -> ToDoLocationMutationResponse {
        try await send(path: "/api/todo/locations", method: .post, body: request)
    }

    func fetchShoppingList() async throws -> ShoppingListResponse {
        try await send(path: "/api/shopping-list")
    }

    func lookupShoppingListItem(named name: String) async throws -> ShoppingListItemLookupResponse {
        try await send(
            path: "/api/shopping-list/items/lookup",
            queryItems: [
                URLQueryItem(name: "name", value: name)
            ]
        )
    }

    func fetchKrogerProductDiagnostic(named name: String = "Soy Milk") async throws -> KrogerProductDiagnosticResponse {
        try await send(
            path: "/api/debug/kroger/products",
            queryItems: [
                URLQueryItem(name: "term", value: name)
            ]
        )
    }

    func searchKrogerProducts(named name: String) async throws -> KrogerProductSearchResponse {
        try await send(
            path: "/api/shopping-list/products/search",
            queryItems: [
                URLQueryItem(name: "term", value: name)
            ]
        )
    }

    func createShoppingListItem(_ request: CreateShoppingListItemRequest) async throws -> ShoppingListMutationResponse {
        try await send(
            path: "/api/shopping-list/items",
            method: .post,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func updateShoppingListItem(
        id itemId: Int,
        _ request: UpdateShoppingListItemRequest
    ) async throws -> ShoppingListMutationResponse {
        try await send(
            path: "/api/shopping-list/items/\(itemId)",
            method: .patch,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func deleteShoppingListItem(id itemId: Int) async throws -> DeleteShoppingListItemResponse {
        let mutationId = UUID().uuidString

        return try await send(
            path: "/api/shopping-list/items/\(itemId)",
            method: .delete,
            additionalHeaders: Self.mutationHeaders(for: mutationId)
        )
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
        queryItems: [URLQueryItem] = [],
        additionalHeaders: [String: String] = [:]
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: nil,
            additionalHeaders: additionalHeaders
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        body: Body,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Response {
        let bodyData: Data

        do {
            bodyData = try encoder.encode(body)
        } catch {
            appLogStore?.record(
                level: .error,
                category: "API",
                title: "Failed to encode request",
                detail: "\(method.rawValue) \(path): \(error.localizedDescription)"
            )
            throw APIError.decoding(error.localizedDescription)
        }

        return try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData,
            additionalHeaders: additionalHeaders
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        additionalHeaders: [String: String]
    ) async throws -> Response {
        let url: URL

        do {
            url = try makeURL(path: path, queryItems: queryItems)
        } catch {
            appLogStore?.record(
                level: .error,
                category: "API",
                title: "Invalid API request URL",
                detail: "\(method.rawValue) \(path): \(error.localizedDescription)"
            )
            throw error
        }

        let requestLabel = "\(method.rawValue) \(Self.displayPath(for: url))"
        appLogStore?.record(
            level: .info,
            category: "API",
            title: "Sending \(requestLabel)",
            detail: url.host.map { "Host: \($0)" }
        )

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        additionalHeaders.forEach { field, value in
            request.setValue(value, forHTTPHeaderField: field)
        }

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            appLogStore?.record(
                level: .error,
                category: "API",
                title: "Network failed for \(requestLabel)",
                detail: error.localizedDescription
            )
            throw APIError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            appLogStore?.record(
                level: .error,
                category: "API",
                title: "Invalid API response",
                detail: "\(requestLabel): response was not HTTP."
            )
            throw APIError.transport("The API returned a non-HTTP response.")
        }

        guard 200...299 ~= httpResponse.statusCode else {
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data),
               !errorResponse.error.isEmpty {
                appLogStore?.record(
                    level: .error,
                    category: "API",
                    title: "HTTP \(httpResponse.statusCode) for \(requestLabel)",
                    detail: errorResponse.error
                )
                throw APIError.server(statusCode: httpResponse.statusCode, message: errorResponse.error)
            }

            appLogStore?.record(
                level: .error,
                category: "API",
                title: "HTTP \(httpResponse.statusCode) for \(requestLabel)",
                detail: "The API returned an unsuccessful status without a readable error body."
            )
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decodedResponse = try decoder.decode(Response.self, from: data)
            appLogStore?.record(
                level: .success,
                category: "API",
                title: "Received HTTP \(httpResponse.statusCode)",
                detail: requestLabel
            )
            return decodedResponse
        } catch {
            appLogStore?.record(
                level: .error,
                category: "API",
                title: "Failed to decode API response",
                detail: "\(requestLabel): \(error.localizedDescription)"
            )
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

protocol DeviceRegistrationServicing {
    func registerDevice(_ request: RegisterDeviceRequest) async throws -> RegisterDeviceResponse
}

extension APIClient: DeviceRegistrationServicing {}

private extension APIClient {
    static let mutationIDHeader = "X-Levy-Home-Mutation-ID"

    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func mutationHeaders(for mutationId: String) -> [String: String] {
        [mutationIDHeader: mutationId]
    }

    static func displayPath(for url: URL) -> String {
        if let query = url.query, !query.isEmpty {
            return "\(url.path)?\(query)"
        }

        return url.path
    }
}
