import Combine
import Foundation

struct HomeOverviewStatusData: Equatable {
    let label: String
    let systemImage: String
    let tone: StatusBadgeTone
}

@MainActor
final class HomeOverviewViewModel: ObservableObject {
    typealias OverviewLoader = () async throws -> HomeOverview
    typealias TodayActivityLoader = (_ limit: Int, _ start: Date, _ end: Date) async throws -> EventsResponse

    @Published private(set) var overview: HomeOverview?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var todayActivityEvents: [LevyHomeEvent] = []
    @Published private(set) var hasLoadedTodayActivity = false

    private let loadOverview: OverviewLoader
    private let loadTodayActivity: TodayActivityLoader
    private let dateFormatter: DateFormattingService
    private let now: () -> Date
    private var calendar: Calendar
    private var hasLoaded = false
    private var loadedActivityDayStart: Date?

    var statusData: HomeOverviewStatusData {
        if isLoading {
            return HomeOverviewStatusData(label: "Loading", systemImage: "arrow.clockwise", tone: .neutral)
        }

        if errorMessage != nil && overview == nil {
            return HomeOverviewStatusData(label: "Offline", systemImage: "wifi.slash", tone: .critical)
        }

        if errorMessage != nil && overview != nil {
            return HomeOverviewStatusData(label: "Stale", systemImage: "exclamationmark.triangle", tone: .warning)
        }

        if overview?.isPartial == true {
            return HomeOverviewStatusData(label: "Partial", systemImage: "exclamationmark.triangle", tone: .warning)
        }

        if overview?.garageStatus.isStale == true {
            return HomeOverviewStatusData(label: "Stale", systemImage: "exclamationmark.triangle", tone: .warning)
        }

        if overview != nil {
            return HomeOverviewStatusData(label: "Live", systemImage: "checkmark.circle", tone: .success)
        }

        return HomeOverviewStatusData(label: "Ready", systemImage: "house", tone: .neutral)
    }

    var statusMessage: String? {
        if let errorMessage, overview != nil {
            return "\(errorMessage) Showing the last loaded home status."
        }

        if overview?.isPartial == true {
            return "Some home status could not be loaded. The available details are shown below."
        }

        if overview?.garageStatus.isStale == true {
            return "Garage status may be stale. Pull to refresh for the latest update."
        }

        return nil
    }

    var garageCardData: GarageStatusCardData {
        guard let garageStatus = overview?.garageStatus else {
            return GarageStatusCardData(
                status: "Loading",
                location: "Main garage",
                detail: "Checking garage status...",
                systemImage: "door.garage.closed",
                tone: .neutral
            )
        }

        let location = garageStatus.displayName ?? "Main garage"

        return GarageStatusCardData(
            status: garageStatus.state.displayTitle,
            location: location,
            detail: garageDetail(for: garageStatus),
            systemImage: garageStatus.state.systemImage,
            tone: garageStatus.state.tone
        )
    }

    var lightSummaryCardData: LightSummaryCardData {
        guard let lightSummary = overview?.lightSummary else {
            return LightSummaryCardData(
                state: "Loading",
                detail: "Checking light status...",
                groups: []
            )
        }

        return LightSummaryCardData(
            state: lightSummary.displayTitle,
            detail: lightSummary.detailText,
            groups: lightSummary.groups.map { group in
                LightGroupSummary(
                    id: group.id,
                    name: group.name,
                    state: group.state,
                    count: group.displayCount
                )
            }
        )
    }

    convenience init(service: HomeStatusServicing, apiClient: APIClient) {
        self.init(
            loadTodayActivity: { limit, start, end in
                try await apiClient.fetchRecentEvents(limit: limit, start: start, end: end)
            },
            loadOverview: { try await service.fetchOverview() }
        )
    }

    init(
        dateFormatter: DateFormattingService = DateFormattingService(),
        now: @escaping () -> Date = Date.init,
        timeZone: TimeZone = TimeZone(identifier: "America/Denver") ?? .current,
        loadTodayActivity: @escaping TodayActivityLoader = { _, _, _ in EventsResponse(ok: true, events: []) },
        loadOverview: @escaping OverviewLoader
    ) {
        self.dateFormatter = dateFormatter
        self.now = now
        self.loadTodayActivity = loadTodayActivity
        self.loadOverview = loadOverview
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
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

    func apply(overview: HomeOverview) {
        self.overview = overview
        errorMessage = nil
        hasLoaded = true
    }

    func refreshTodayActivityIfDayChanged() async {
        let range = activityDayRange(for: now())
        guard loadedActivityDayStart != range.start else {
            return
        }

        // Never carry yesterday's rows across the Mountain-time midnight boundary,
        // including when the following request is unavailable.
        todayActivityEvents = []
        hasLoadedTodayActivity = false
        await refreshTodayActivity()
    }

    func secondsUntilNextMountainMidnight() -> TimeInterval {
        let range = activityDayRange(for: now())
        return max(range.end.timeIntervalSince(now()), 1)
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
            overview = try await loadOverview()
            errorMessage = nil
            hasLoaded = true
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            errorMessage = error.localizedDescription
            hasLoaded = true
        }

        await refreshTodayActivity()
    }

    private func refreshTodayActivity() async {
        let range = activityDayRange(for: now())

        do {
            let response = try await loadTodayActivity(500, range.start, range.end)
            todayActivityEvents = response.events
                .filter { range.contains(eventDate($0)) }
                .sorted { eventDate($0) > eventDate($1) }
            loadedActivityDayStart = range.start
            hasLoadedTodayActivity = true
        } catch is CancellationError {
            return
        } catch {
            // Activity is supplementary to the Home overview. Keep its prior state rather than
            // presenting an empty-day message when the feed could not be loaded.
        }
    }

    private func activityDayRange(for date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    private func eventDate(_ event: LevyHomeEvent) -> Date {
        Self.isoFormatterWithFractionalSeconds.date(from: event.occurredAt) ??
            Self.isoFormatter.date(from: event.occurredAt) ??
            .distantPast
    }

    private func garageDetail(for garageStatus: GarageStatus) -> String {
        var details: [String] = []

        if let lastUpdatedAt = garageStatus.lastUpdatedAt {
            details.append("Updated \(dateFormatter.displayString(for: lastUpdatedAt))")
        } else {
            details.append("No update time is available.")
        }

        if garageStatus.isStale == true {
            details.append("Status may be stale.")
        }

        if garageStatus.state.isUnknown {
            details.append("Garage status is unavailable.")
        }

        return details.joined(separator: " ")
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

private extension GarageStatus.State {
    var displayTitle: String {
        switch self {
        case .open:
            return "Open"
        case .closed:
            return "Closed"
        case .opening:
            return "Opening"
        case .closing:
            return "Closing"
        case .unknown:
            return "Unknown"
        case .unrecognized:
            return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .open:
            return "door.garage.open"
        case .closed:
            return "door.garage.closed"
        case .opening, .closing:
            return "door.garage.open"
        case .unknown, .unrecognized:
            return "questionmark.circle"
        }
    }

    var tone: StatusBadgeTone {
        switch self {
        case .open:
            return .warning
        case .closed:
            return .success
        case .opening, .closing:
            return .accent
        case .unknown, .unrecognized:
            return .neutral
        }
    }

    var isUnknown: Bool {
        switch self {
        case .unknown, .unrecognized:
            return true
        case .open, .closed, .opening, .closing:
            return false
        }
    }
}

private extension LightSummary {
    var displayTitle: String {
        switch state {
        case .off:
            return "All lights off"
        case .on, .partiallyOn:
            guard let lightsOnCount else {
                return "Lights on"
            }

            return lightsOnCount == 1 ? "1 light on" : "\(lightsOnCount) lights on"
        case .unavailable:
            return "Light status unavailable"
        case .unknown, .unrecognized:
            return "Unknown"
        }
    }

    var detailText: String {
        switch state {
        case .off:
            return "No configured lights are currently on."
        case .on:
            if let lightsOnCount, let totalLightCount {
                return "\(lightsOnCount) of \(totalLightCount) configured lights are on."
            }

            return "Configured lights are currently on."
        case .partiallyOn:
            if let lightsOnCount, let totalLightCount {
                return "\(lightsOnCount) of \(totalLightCount) configured lights are still on."
            }

            return "Some configured lights are still on."
        case .unavailable:
            return "One or more configured lights are unavailable. Pull to refresh or check Home Assistant."
        case .unknown, .unrecognized:
            return "Light status is unavailable. Pull to refresh or check the API connection."
        }
    }
}

private extension LightGroupStatus {
    var displayCount: String {
        if let lightsOnCount, let totalLightCount {
            if lightsOnCount == 0 {
                return "Off"
            }

            if lightsOnCount == totalLightCount {
                return "All on"
            }

            return "\(lightsOnCount)/\(totalLightCount) on"
        }

        switch state {
        case .off:
            return "Off"
        case .on:
            return "On"
        case .partiallyOn:
            return "Some on"
        case .unavailable:
            return "Unavailable"
        case .unknown, .unrecognized:
            return "Unknown"
        }
    }
}

private extension DisplaySeverity {
    var displayTitle: String {
        switch self {
        case .info:
            return "Info"
        case .warning:
            return "Important"
        case .critical:
            return "Critical"
        case .unknown:
            return "Event"
        }
    }

    var tone: StatusBadgeTone {
        switch self {
        case .info:
            return .accent
        case .warning:
            return .warning
        case .critical:
            return .critical
        case .unknown:
            return .neutral
        }
    }
}
