import Foundation

extension APIClient {
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
}
