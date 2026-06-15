import Combine
import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    typealias EventLoader = (_ limit: Int, _ start: Date, _ end: Date) async throws -> EventsResponse

    @Published private(set) var events: [LevyHomeEvent] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingOlder = false

    private let eventLimit: Int
    private let windowDuration: TimeInterval
    private let now: () -> Date
    private let loadEvents: EventLoader
    private var hasLoaded = false
    private var oldestLoadedStart: Date?

    var isEmpty: Bool {
        hasLoaded && events.isEmpty && errorMessage == nil && !isLoading && !isLoadingOlder
    }

    convenience init(apiClient: APIClient, eventLimit: Int = 500, windowHours: TimeInterval = 24) {
        self.init(eventLimit: eventLimit, windowHours: windowHours) { limit, start, end in
            try await apiClient.fetchRecentEvents(limit: limit, start: start, end: end)
        }
    }

    init(
        eventLimit: Int = 500,
        windowHours: TimeInterval = 24,
        now: @escaping () -> Date = Date.init,
        loadEvents: @escaping EventLoader
    ) {
        self.eventLimit = eventLimit
        self.windowDuration = windowHours * 60 * 60
        self.now = now
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

    func loadOlderIfNeeded(currentEvent: LevyHomeEvent) async {
        guard currentEvent.id == events.last?.id else {
            return
        }

        await loadOlder()
    }

    func loadOlder() async {
        guard hasLoaded, !isLoading, !isRefreshing, !isLoadingOlder else {
            return
        }

        let end = oldestLoadedStart ?? now()
        let start = end.addingTimeInterval(-windowDuration)

        isLoadingOlder = true

        defer {
            isLoadingOlder = false
        }

        do {
            let response = try await loadEvents(eventLimit, start, end)
            oldestLoadedStart = start
            events = mergedEvents(existing: events, incoming: response.events)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(isRefresh: Bool) async {
        guard !isLoading, !isRefreshing, !isLoadingOlder else {
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
            let end = now()
            let start = end.addingTimeInterval(-windowDuration)
            let response = try await loadEvents(eventLimit, start, end)
            events = sortedEvents(response.events)
            oldestLoadedStart = start
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }

    private func mergedEvents(existing: [LevyHomeEvent], incoming: [LevyHomeEvent]) -> [LevyHomeEvent] {
        var eventsById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for event in incoming where eventsById[event.id] == nil {
            eventsById[event.id] = event
        }

        return sortedEvents(Array(eventsById.values))
    }

    private func sortedEvents(_ events: [LevyHomeEvent]) -> [LevyHomeEvent] {
        events.sorted { first, second in
            eventDate(first) > eventDate(second)
        }
    }

    private func eventDate(_ event: LevyHomeEvent) -> Date {
        Self.isoFormatterWithFractionalSeconds.date(from: event.occurredAt) ??
            Self.isoFormatter.date(from: event.occurredAt) ??
            .distantPast
    }

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
