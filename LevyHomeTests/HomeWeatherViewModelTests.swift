import Foundation
import XCTest
@testable import LevyHome

@MainActor
final class HomeWeatherViewModelTests: XCTestCase {
    func testStaticHomeLocationProviderUsesLevyHomeCoordinate() async throws {
        let location = try await StaticHomeLocationProvider.levyHome.location()

        XCTAssertEqual(location.coordinate.latitude, 39.5388289, accuracy: 0.000001)
        XCTAssertEqual(location.coordinate.longitude, -105.0305231, accuracy: 0.000001)
    }

    func testLoadIfNeededLoadsWeatherSnapshot() async {
        let now = Self.date("2026-07-01T16:00:00Z")
        let viewModel = HomeWeatherViewModel(now: { now }) {
            Self.snapshot(
                current: 73.4,
                high: 82.2,
                low: 57.7,
                condition: "Partly Cloudy",
                symbolName: "cloud.sun.fill",
                fetchedAt: now
            )
        }

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.displayData.dateText, "Wed. Jul 1")
        XCTAssertEqual(viewModel.displayData.currentTemperatureText, "73°")
        XCTAssertEqual(viewModel.displayData.highLowTemperatureText, "82°/58°")
        XCTAssertEqual(viewModel.displayData.conditionText, "Partly Cloudy")
        XCTAssertEqual(viewModel.displayData.systemImage, "cloud.sun.fill")
        XCTAssertFalse(viewModel.displayData.isPlaceholder)
        XCTAssertFalse(viewModel.displayData.isStale)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadIfNeededDoesNotReloadAfterFirstLoad() async {
        var loadCount = 0
        let viewModel = HomeWeatherViewModel {
            loadCount += 1
            return Self.snapshot(current: Double(70 + loadCount))
        }

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(viewModel.displayData.currentTemperatureText, "71°")
    }

    func testFailureWithoutSnapshotShowsUnavailablePlaceholder() async {
        let viewModel = HomeWeatherViewModel {
            throw HomeWeatherServiceError.homeLocationUnavailable
        }

        await viewModel.loadIfNeeded()

        XCTAssertNil(viewModel.snapshot)
        XCTAssertEqual(viewModel.errorMessage, "Weather is unavailable.")
        XCTAssertEqual(viewModel.displayData.conditionText, "Weather unavailable")
        XCTAssertTrue(viewModel.displayData.isPlaceholder)
        XCTAssertTrue(viewModel.displayData.isStale)
    }

    func testFailedRefreshKeepsSnapshotAndMarksWeatherStale() async {
        let now = Self.date("2026-07-01T16:00:00Z")
        var responses: [Result<HomeWeatherSnapshot, Error>] = [
            .success(Self.snapshot(current: 74, fetchedAt: now)),
            .failure(HomeWeatherServiceError.homeLocationUnavailable)
        ]
        let viewModel = HomeWeatherViewModel(now: { now }) {
            try responses.removeFirst().get()
        }

        await viewModel.loadIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.displayData.currentTemperatureText, "74°")
        XCTAssertEqual(viewModel.errorMessage, "Weather is unavailable.")
        XCTAssertTrue(viewModel.displayData.isStale)
        XCTAssertFalse(viewModel.displayData.isPlaceholder)
    }

    func testExpandedDataUsesDaytimeForecastWindow() async {
        let now = Self.date("2026-07-01T16:00:00Z")
        let viewModel = HomeWeatherViewModel(now: { now }, calendar: Self.utcCalendar) {
            Self.snapshot(
                current: 73,
                high: 91,
                low: 52,
                hourlyForecast: [
                    Self.hourly("2026-07-01T06:00:00Z", temperature: 65),
                    Self.hourly("2026-07-01T08:00:00Z", temperature: 68),
                    Self.hourly("2026-07-01T12:00:00Z", temperature: 77),
                    Self.hourly("2026-07-01T14:00:00Z", temperature: 80, condition: "Rain", chance: 0.45, precipitation: "rain"),
                    Self.hourly("2026-07-01T15:00:00Z", temperature: 82, condition: "Rain", chance: 0.42, precipitation: "rain"),
                    Self.hourly("2026-07-01T16:00:00Z", temperature: 84),
                    Self.hourly("2026-07-01T20:00:00Z", temperature: 74),
                    Self.hourly("2026-07-01T22:00:00Z", temperature: 69),
                    Self.hourly("2026-07-02T06:00:00Z", temperature: 65),
                    Self.hourly("2026-07-02T09:00:00Z", temperature: 83),
                    Self.hourly("2026-07-02T12:00:00Z", temperature: 87, chance: 0.20),
                    Self.hourly("2026-07-02T15:00:00Z", temperature: 90, chance: 0.35),
                    Self.hourly("2026-07-02T18:00:00Z", temperature: 86, chance: 0.15),
                    Self.hourly("2026-07-02T21:00:00Z", temperature: 79),
                    Self.hourly("2026-07-02T22:00:00Z", temperature: 74)
                ],
                dailyForecast: [
                    HomeWeatherDailyForecast(
                        date: Self.date("2026-07-01T00:00:00Z"),
                        highTemperature: Measurement(value: 91, unit: UnitTemperature.fahrenheit),
                        lowTemperature: Measurement(value: 52, unit: UnitTemperature.fahrenheit),
                        precipitationChance: 0.1
                    ),
                    HomeWeatherDailyForecast(
                        date: Self.date("2026-07-02T00:00:00Z"),
                        highTemperature: Measurement(value: 94, unit: UnitTemperature.fahrenheit),
                        lowTemperature: Measurement(value: 55, unit: UnitTemperature.fahrenheit),
                        precipitationChance: 0.2
                    )
                ]
            )
        }

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.displayData.highLowTemperatureText, "84°/65°")
        XCTAssertEqual(viewModel.expandedData.chart.xAxisLabels.map(\.label), ["8 AM", "12 PM", "4 PM", "8 PM"])
        XCTAssertEqual(viewModel.expandedData.chart.yAxisValues.first, 89)
        XCTAssertEqual(viewModel.expandedData.chart.yAxisValues.last, 60)
        XCTAssertEqual(viewModel.expandedData.precipitationSummary, "Chance of light rain in the afternoon.")
        XCTAssertEqual(viewModel.expandedData.tomorrow.highText, "90°")
        XCTAssertEqual(viewModel.expandedData.tomorrow.lowText, "65°")
        XCTAssertEqual(viewModel.expandedData.tomorrow.averageText, "81°")
        XCTAssertEqual(viewModel.expandedData.tomorrow.precipitationChanceText, "35%")
    }

    private static func snapshot(
        current: Double,
        high: Double? = 82,
        low: Double? = 58,
        condition: String = "Clear",
        symbolName: String = "sun.max.fill",
        fetchedAt: Date = Date(),
        hourlyForecast: [HomeWeatherForecastPoint] = [],
        dailyForecast: [HomeWeatherDailyForecast] = []
    ) -> HomeWeatherSnapshot {
        HomeWeatherSnapshot(
            currentTemperature: Measurement(value: current, unit: UnitTemperature.fahrenheit),
            highTemperature: high.map { Measurement(value: $0, unit: UnitTemperature.fahrenheit) },
            lowTemperature: low.map { Measurement(value: $0, unit: UnitTemperature.fahrenheit) },
            conditionDescription: condition,
            symbolName: symbolName,
            attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
            fetchedAt: fetchedAt,
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast
        )
    }

    private static func hourly(
        _ date: String,
        temperature: Double,
        condition: String = "Clear",
        chance: Double = 0,
        precipitation: String = "none"
    ) -> HomeWeatherForecastPoint {
        HomeWeatherForecastPoint(
            date: Self.date(date),
            temperature: Measurement(value: temperature, unit: UnitTemperature.fahrenheit),
            conditionDescription: condition,
            precipitationChance: chance,
            precipitationDescription: precipitation
        )
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
