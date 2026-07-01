import Foundation

struct HomeWeatherSummaryData: Equatable {
    let dateText: String
    let attributionURL: URL?
    let systemImage: String
    let currentTemperatureText: String
    let highLowTemperatureText: String
    let conditionText: String
    let isPlaceholder: Bool
    let isStale: Bool

    var accessibilityLabel: String {
        if isPlaceholder {
            return "Weather, \(dateText), \(conditionText)."
        }

        let staleText = isStale ? " Data may be stale." : ""
        return "Weather, \(dateText), \(conditionText), current \(currentTemperatureText), high and low \(highLowTemperatureText).\(staleText)"
    }

    static func placeholder(
        dateText: String,
        message: String = "Loading weather",
        isStale: Bool = false
    ) -> HomeWeatherSummaryData {
        HomeWeatherSummaryData(
            dateText: dateText,
            attributionURL: nil,
            systemImage: "cloud.sun.fill",
            currentTemperatureText: "--",
            highLowTemperatureText: "--/--",
            conditionText: message,
            isPlaceholder: true,
            isStale: isStale
        )
    }
}

@MainActor
final class HomeWeatherViewModel: ObservableObject {
    typealias SnapshotLoader = () async throws -> HomeWeatherSnapshot

    @Published private(set) var snapshot: HomeWeatherSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false

    private let loadSnapshot: SnapshotLoader
    private let now: () -> Date
    private let calendar: Calendar
    private let dateFormatter: DateFormatter
    private var hasLoaded = false

    var displayData: HomeWeatherSummaryData {
        let dateText = dateFormatter.string(from: now())

        guard let snapshot else {
            return .placeholder(
                dateText: dateText,
                message: errorMessage == nil ? "Loading weather" : "Weather unavailable",
                isStale: errorMessage != nil
            )
        }

        return HomeWeatherSummaryData(
            dateText: dateText,
            attributionURL: snapshot.attributionURL,
            systemImage: snapshot.symbolName,
            currentTemperatureText: Self.temperatureText(snapshot.currentTemperature),
            highLowTemperatureText: highLowText(for: snapshot),
            conditionText: snapshot.conditionDescription,
            isPlaceholder: false,
            isStale: errorMessage != nil || isSnapshotStale(snapshot)
        )
    }

    convenience init(service: HomeWeatherServicing) {
        self.init {
            try await service.fetchSnapshot()
        }
    }

    init(
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        loadSnapshot: @escaping SnapshotLoader
    ) {
        self.now = now
        self.calendar = calendar
        self.loadSnapshot = loadSnapshot

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE. MMM d"
        self.dateFormatter = formatter
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
            snapshot = try await loadSnapshot()
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = "Weather is unavailable."
            hasLoaded = true
        }
    }

    private func highLowText(for snapshot: HomeWeatherSnapshot) -> String {
        guard let highTemperature = snapshot.highTemperature,
              let lowTemperature = snapshot.lowTemperature else {
            return "--/--"
        }

        return "\(Self.temperatureText(highTemperature))/\(Self.temperatureText(lowTemperature))"
    }

    private func isSnapshotStale(_ snapshot: HomeWeatherSnapshot) -> Bool {
        !calendar.isDate(snapshot.fetchedAt, inSameDayAs: now())
    }

    private static func temperatureText(_ temperature: Measurement<UnitTemperature>) -> String {
        let fahrenheit = temperature.converted(to: .fahrenheit).value.rounded()
        return "\(Int(fahrenheit))°"
    }
}
