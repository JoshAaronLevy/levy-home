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

struct HomeWeatherExpandedData: Equatable {
    let summary: HomeWeatherSummaryData
    let chart: HomeWeatherChartData
    let precipitationSummary: String
    let tomorrow: HomeWeatherTomorrowSummaryData
}

struct HomeWeatherChartData: Equatable {
    let points: [HomeWeatherChartPoint]
    let xAxisLabels: [HomeWeatherAxisLabel]
    let yAxisValues: [Int]
    let minimumTemperature: Double
    let maximumTemperature: Double

    static let placeholder = HomeWeatherChartData(
        points: [],
        xAxisLabels: Self.standardXAxisLabels,
        yAxisValues: [85, 75, 65, 55],
        minimumTemperature: 55,
        maximumTemperature: 85
    )

    static let standardXAxisLabels = [
        HomeWeatherAxisLabel(label: "8 AM", position: 0.125),
        HomeWeatherAxisLabel(label: "12 PM", position: 0.375),
        HomeWeatherAxisLabel(label: "4 PM", position: 0.625),
        HomeWeatherAxisLabel(label: "8 PM", position: 0.875)
    ]
}

struct HomeWeatherChartPoint: Equatable, Identifiable {
    let id: TimeInterval
    let position: Double
    let temperature: Double
}

struct HomeWeatherAxisLabel: Equatable, Identifiable {
    let label: String
    let position: Double

    var id: String { label }
}

struct HomeWeatherTomorrowSummaryData: Equatable {
    let highText: String
    let lowText: String
    let averageText: String
    let precipitationChanceText: String

    static let placeholder = HomeWeatherTomorrowSummaryData(
        highText: "--",
        lowText: "--",
        averageText: "--",
        precipitationChanceText: "--"
    )
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
            highLowTemperatureText: highLowText(for: snapshot, on: now()),
            conditionText: snapshot.conditionDescription,
            isPlaceholder: false,
            isStale: errorMessage != nil || isSnapshotStale(snapshot)
        )
    }

    var expandedData: HomeWeatherExpandedData {
        guard let snapshot else {
            return HomeWeatherExpandedData(
                summary: displayData,
                chart: .placeholder,
                precipitationSummary: "Weather details are unavailable.",
                tomorrow: .placeholder
            )
        }

        return HomeWeatherExpandedData(
            summary: displayData,
            chart: chartData(for: snapshot, on: now()),
            precipitationSummary: precipitationSummary(for: daytimeForecastPoints(in: snapshot, on: now())),
            tomorrow: tomorrowSummary(for: snapshot)
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
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
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

    private func highLowText(for snapshot: HomeWeatherSnapshot, on date: Date) -> String {
        let range = daytimeTemperatureRange(in: snapshot, on: date)
        let highTemperature = range?.high ?? snapshot.highTemperature
        let lowTemperature = range?.low ?? snapshot.lowTemperature

        guard let highTemperature, let lowTemperature else {
            return "--/--"
        }

        return "\(Self.temperatureText(highTemperature))/\(Self.temperatureText(lowTemperature))"
    }

    private func chartData(for snapshot: HomeWeatherSnapshot, on date: Date) -> HomeWeatherChartData {
        let points = daytimeForecastPoints(in: snapshot, on: date)
        let range = daytimeTemperatureRange(in: snapshot, on: date)
        let fallbackLow = snapshot.lowTemperature?.converted(to: .fahrenheit).value
        let fallbackHigh = snapshot.highTemperature?.converted(to: .fahrenheit).value
        let low = range?.low.converted(to: .fahrenheit).value ?? fallbackLow ?? 55
        let high = range?.high.converted(to: .fahrenheit).value ?? fallbackHigh ?? 85
        let minimumTemperature = floor(low) - 5
        let maximumTemperature = ceil(high) + 5

        return HomeWeatherChartData(
            points: points.map { point in
                HomeWeatherChartPoint(
                    id: point.date.timeIntervalSinceReferenceDate,
                    position: daytimePosition(for: point.date),
                    temperature: point.temperature.converted(to: .fahrenheit).value
                )
            },
            xAxisLabels: HomeWeatherChartData.standardXAxisLabels,
            yAxisValues: yAxisValues(minimum: minimumTemperature, maximum: maximumTemperature),
            minimumTemperature: minimumTemperature,
            maximumTemperature: maximumTemperature
        )
    }

    private func tomorrowSummary(for snapshot: HomeWeatherSnapshot) -> HomeWeatherTomorrowSummaryData {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now()) else {
            return .placeholder
        }

        let points = daytimeForecastPoints(in: snapshot, on: tomorrow)
        let dailyForecast = snapshot.dailyForecast.first { calendar.isDate($0.date, inSameDayAs: tomorrow) }
        let range = temperatureRange(in: points)
        let highTemperature = range?.high ?? dailyForecast?.highTemperature
        let lowTemperature = range?.low ?? dailyForecast?.lowTemperature
        let averageTemperature = averageTemperature(in: points)
        let precipitationChance = points.map(\.precipitationChance).max() ?? dailyForecast?.precipitationChance

        return HomeWeatherTomorrowSummaryData(
            highText: highTemperature.map(Self.temperatureText) ?? "--",
            lowText: lowTemperature.map(Self.temperatureText) ?? "--",
            averageText: averageTemperature.map(Self.temperatureText) ?? "--",
            precipitationChanceText: precipitationChance.map(Self.percentText) ?? "--"
        )
    }

    private func precipitationSummary(for points: [HomeWeatherForecastPoint]) -> String {
        let wetPoints = points.filter { point in
            point.precipitationChance >= 0.2 || precipitationKind(for: point) != nil
        }

        guard !wetPoints.isEmpty else {
            return "No meaningful precipitation expected today."
        }

        let maximumChance = wetPoints.map(\.precipitationChance).max() ?? 0
        let kind = wetPoints.compactMap(precipitationKind).first ?? "precipitation"
        let eventText = precipitationEventText(kind: kind, maximumChance: maximumChance)
        let timeText = precipitationTimeText(for: wetPoints)

        return "\(eventText) \(timeText)."
    }

    private func precipitationKind(for point: HomeWeatherForecastPoint) -> String? {
        let description = "\(point.conditionDescription) \(point.precipitationDescription)".lowercased()

        if description.contains("thunder") {
            return "thunderstorms"
        }

        if description.contains("snow") {
            return "snow"
        }

        if description.contains("shower") {
            return "showers"
        }

        if description.contains("rain") || description.contains("drizzle") {
            return point.precipitationChance >= 0.55 ? "rain" : "light rain"
        }

        return point.precipitationChance >= 0.35 ? "precipitation" : nil
    }

    private func precipitationEventText(kind: String, maximumChance: Double) -> String {
        if maximumChance >= 0.65 {
            return "\(kind.capitalized) likely"
        }

        if maximumChance >= 0.35 {
            return "Chance of \(kind)"
        }

        return "Slight chance of \(kind)"
    }

    private func precipitationTimeText(for points: [HomeWeatherForecastPoint]) -> String {
        let parts = Set(points.map(dayPart))

        if parts == ["morning"] {
            return "this morning"
        }

        if parts == ["afternoon"] {
            return "in the afternoon"
        }

        if parts == ["evening"] {
            return "this evening"
        }

        if parts == ["afternoon", "evening"] {
            return "late afternoon into evening"
        }

        return "through the day"
    }

    private func dayPart(for point: HomeWeatherForecastPoint) -> String {
        let hour = calendar.component(.hour, from: point.date)

        if hour < 12 {
            return "morning"
        }

        if hour < 17 {
            return "afternoon"
        }

        return "evening"
    }

    private func daytimeForecastPoints(in snapshot: HomeWeatherSnapshot, on date: Date) -> [HomeWeatherForecastPoint] {
        snapshot.hourlyForecast
            .filter { point in
                guard calendar.isDate(point.date, inSameDayAs: date) else {
                    return false
                }

                let hour = calendar.component(.hour, from: point.date)
                return hour >= 6 && hour <= 22
            }
            .sorted { $0.date < $1.date }
    }

    private func daytimeTemperatureRange(
        in snapshot: HomeWeatherSnapshot,
        on date: Date
    ) -> (high: Measurement<UnitTemperature>, low: Measurement<UnitTemperature>)? {
        let points = daytimeForecastPoints(in: snapshot, on: date)
        guard points.count >= 4 else {
            return nil
        }

        return temperatureRange(in: points)
    }

    private func temperatureRange(
        in points: [HomeWeatherForecastPoint]
    ) -> (high: Measurement<UnitTemperature>, low: Measurement<UnitTemperature>)? {
        let temperatures = points.map(\.temperature)
        guard let high = temperatures.max(by: { $0.converted(to: .fahrenheit).value < $1.converted(to: .fahrenheit).value }),
              let low = temperatures.min(by: { $0.converted(to: .fahrenheit).value < $1.converted(to: .fahrenheit).value }) else {
            return nil
        }

        return (high: high, low: low)
    }

    private func averageTemperature(in points: [HomeWeatherForecastPoint]) -> Measurement<UnitTemperature>? {
        guard !points.isEmpty else {
            return nil
        }

        let average = points
            .map { $0.temperature.converted(to: .fahrenheit).value }
            .reduce(0, +) / Double(points.count)
        return Measurement(value: average, unit: UnitTemperature.fahrenheit)
    }

    private func daytimePosition(for date: Date) -> Double {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let value = Double(hour) + Double(minute) / 60
        return min(max((value - 6) / 16, 0), 1)
    }

    private func yAxisValues(minimum: Double, maximum: Double) -> [Int] {
        guard maximum > minimum else {
            return [Int(maximum.rounded()), Int(minimum.rounded())]
        }

        let step = (maximum - minimum) / 4
        return (0...4).map { index in
            Int((maximum - Double(index) * step).rounded())
        }
    }

    private func isSnapshotStale(_ snapshot: HomeWeatherSnapshot) -> Bool {
        !calendar.isDate(snapshot.fetchedAt, inSameDayAs: now())
    }

    private static func temperatureText(_ temperature: Measurement<UnitTemperature>) -> String {
        let fahrenheit = temperature.converted(to: .fahrenheit).value.rounded()
        return "\(Int(fahrenheit))°"
    }

    private static func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
