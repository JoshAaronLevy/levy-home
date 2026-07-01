import Foundation
import XCTest
@testable import LevyHome

@MainActor
final class HomeWeatherViewModelTests: XCTestCase {
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

    private static func snapshot(
        current: Double,
        high: Double? = 82,
        low: Double? = 58,
        condition: String = "Clear",
        symbolName: String = "sun.max.fill",
        fetchedAt: Date = Date()
    ) -> HomeWeatherSnapshot {
        HomeWeatherSnapshot(
            currentTemperature: Measurement(value: current, unit: UnitTemperature.fahrenheit),
            highTemperature: high.map { Measurement(value: $0, unit: UnitTemperature.fahrenheit) },
            lowTemperature: low.map { Measurement(value: $0, unit: UnitTemperature.fahrenheit) },
            conditionDescription: condition,
            symbolName: symbolName,
            attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
            fetchedAt: fetchedAt
        )
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
