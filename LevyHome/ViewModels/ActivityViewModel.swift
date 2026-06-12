import Combine
import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    typealias EventLoader = (_ limit: Int) async throws -> EventsResponse

    @Published private(set) var events: [LevyHomeEvent] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false

    private let eventLimit: Int
    private let loadEvents: EventLoader
    private var hasLoaded = false

    var isEmpty: Bool {
        hasLoaded && events.isEmpty && errorMessage == nil && !isLoading
    }

    convenience init(apiClient: APIClient, eventLimit: Int = 50) {
        self.init(eventLimit: eventLimit) { limit in
            try await apiClient.fetchRecentEvents(limit: limit)
        }
    }

    init(eventLimit: Int = 50, loadEvents: @escaping EventLoader) {
        self.eventLimit = eventLimit
        self.loadEvents = loadEvents
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await load(isRefresh: false)
    }

    func refresh() async {
        await load(isRefresh: true)
    }

    private func load(isRefresh: Bool) async {
        guard !isLoading, !isRefreshing else {
            return
        }

        if isRefresh {
            isRefreshing = true
        } else {
            isLoading = true
        }

        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let response = try await loadEvents(eventLimit)
            events = response.events
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }
}
