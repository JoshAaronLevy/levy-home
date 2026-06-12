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

    @Published private(set) var overview: HomeOverview?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false

    private let loadOverview: OverviewLoader
    private let dateFormatter: DateFormattingService
    private var hasLoaded = false

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
                    count: group.displayCount
                )
            }
        )
    }

    var recentImportantEventData: RecentImportantEventData {
        guard let event = overview?.recentImportantEvent else {
            return RecentImportantEventData(
                title: "No recent important events",
                detail: "High-signal home events will appear here after Home Assistant sends them.",
                timestamp: generatedAtText,
                badgeLabel: "Quiet",
                tone: .neutral
            )
        }

        return RecentImportantEventData(
            title: event.display.title,
            detail: event.display.body,
            timestamp: dateFormatter.displayString(for: event.receivedAt),
            badgeLabel: event.display.severity.displayTitle,
            tone: event.display.severity.tone
        )
    }

    var quickActions: [QuickActionDisplayData] {
        PreviewData.quickActions
    }

    convenience init(service: HomeStatusServicing) {
        self.init {
            try await service.fetchOverview()
        }
    }

    init(
        dateFormatter: DateFormattingService = DateFormattingService(),
        loadOverview: @escaping OverviewLoader
    ) {
        self.dateFormatter = dateFormatter
        self.loadOverview = loadOverview
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
            overview = try await loadOverview()
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }

    private var generatedAtText: String {
        guard let generatedAt = overview?.generatedAt else {
            return "Waiting for live data"
        }

        return "Updated \(dateFormatter.displayString(for: generatedAt))"
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
