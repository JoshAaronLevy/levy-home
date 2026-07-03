import Foundation
import CoreLocation
import XCTest
@testable import LevyHome

@MainActor
final class HomeWeatherViewModelTests: XCTestCase {
    func testStaticHomeLocationProviderUsesLevyHomeCoordinate() async throws {
        let location = try await StaticHomeLocationProvider.levyHome.location()

        XCTAssertEqual(location.coordinate.latitude, 39.5388289, accuracy: 0.000001)
        XCTAssertEqual(location.coordinate.longitude, -105.0305231, accuracy: 0.000001)
    }

    func testHomeWeatherServiceFallsBackWhenPrimaryWeatherProviderFails() async throws {
        let now = Self.date("2026-07-01T16:00:00Z")
        let fallbackSnapshot = Self.snapshot(current: 78, condition: "Rain", fetchedAt: now)
        let primaryProvider = MockCoordinateWeatherProvider(
            result: .failure(HomeWeatherServiceError.homeLocationUnavailable)
        )
        let fallbackProvider = MockCoordinateWeatherProvider(result: .success(fallbackSnapshot))
        let service = HomeWeatherService(
            homeLocationProvider: StaticHomeLocationProvider(latitude: 39.5, longitude: -105),
            primaryWeatherProvider: primaryProvider,
            fallbackWeatherProvider: fallbackProvider,
            now: { now }
        )

        let snapshot = try await service.fetchSnapshot()

        XCTAssertEqual(snapshot.currentTemperature, fallbackSnapshot.currentTemperature)
        XCTAssertEqual(snapshot.conditionDescription, "Rain")
        XCTAssertEqual(primaryProvider.requestCount, 1)
        XCTAssertEqual(fallbackProvider.requestCount, 1)
    }

    func testHomeWeatherServiceDoesNotFallbackWhenPrimaryRequestIsCancelled() async {
        let now = Self.date("2026-07-01T16:00:00Z")
        let primaryProvider = MockCoordinateWeatherProvider(
            result: .failure(CancellationError())
        )
        let fallbackProvider = MockCoordinateWeatherProvider(
            result: .success(Self.snapshot(current: 78, fetchedAt: now))
        )
        let service = HomeWeatherService(
            homeLocationProvider: StaticHomeLocationProvider(latitude: 39.5, longitude: -105),
            primaryWeatherProvider: primaryProvider,
            fallbackWeatherProvider: fallbackProvider,
            now: { now }
        )

        do {
            _ = try await service.fetchSnapshot()
            XCTFail("Expected cancellation to be preserved.")
        } catch {
            XCTAssertTrue(error.isTaskCancellation)
        }

        XCTAssertEqual(primaryProvider.requestCount, 1)
        XCTAssertEqual(fallbackProvider.requestCount, 0)
    }

    func testHomeWeatherServiceFallsBackWhenPrimaryWeatherProviderTimesOut() async throws {
        let now = Self.date("2026-07-01T16:00:00Z")
        let fallbackSnapshot = Self.snapshot(current: 81, condition: "Clear", fetchedAt: now)
        let primaryProvider = HangingCoordinateWeatherProvider()
        let fallbackProvider = MockCoordinateWeatherProvider(result: .success(fallbackSnapshot))
        let service = HomeWeatherService(
            homeLocationProvider: StaticHomeLocationProvider(latitude: 39.5, longitude: -105),
            primaryWeatherProvider: primaryProvider,
            fallbackWeatherProvider: fallbackProvider,
            now: { now },
            providerTimeout: .milliseconds(10)
        )

        let snapshot = try await service.fetchSnapshot()

        XCTAssertEqual(snapshot.currentTemperature, fallbackSnapshot.currentTemperature)
        XCTAssertEqual(snapshot.conditionDescription, "Clear")
        XCTAssertEqual(primaryProvider.requestCount, 1)
        XCTAssertEqual(fallbackProvider.requestCount, 1)
    }

    func testOpenMeteoProviderBuildsFallbackSnapshot() async throws {
        let now = Self.date("2026-07-01T16:00:00Z")
        var capturedRequest: URLRequest?
        MockWeatherURLProtocol.requestHandler = { request in
            capturedRequest = request
            return Self.response(
                for: request,
                json: """
                {
                  "timezone": "America/Denver",
                  "current": {
                    "time": "2026-07-01T14:00",
                    "temperature_2m": 76.2,
                    "weather_code": 61,
                    "precipitation": 0.03
                  },
                  "hourly": {
                    "time": ["2026-07-01T14:00", "2026-07-01T15:00"],
                    "temperature_2m": [76.2, 78.1],
                    "precipitation_probability": [30, 45],
                    "precipitation": [0.02, 0.04],
                    "weather_code": [61, 80]
                  },
                  "daily": {
                    "time": ["2026-07-01", "2026-07-02"],
                    "temperature_2m_max": [82.4, 86.1],
                    "temperature_2m_min": [58.2, 62.0],
                    "precipitation_probability_max": [45, 20],
                    "weather_code": [61, 2]
                  }
                }
                """
            )
        }
        defer { MockWeatherURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWeatherURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let provider = OpenMeteoHomeWeatherProvider(
            baseURL: URL(string: "https://api.open-meteo.test/v1/forecast")!,
            session: session
        )

        let snapshot = try await provider.fetchSnapshot(
            for: CLLocation(latitude: 39.5388289, longitude: -105.0305231),
            fetchedAt: now
        )
        let queryItems = Dictionary(
            uniqueKeysWithValues: (URLComponents(
                url: try XCTUnwrap(capturedRequest?.url),
                resolvingAgainstBaseURL: false
            )?.queryItems ?? []).map { ($0.name, $0.value) }
        )

        XCTAssertEqual(capturedRequest?.url?.host, "api.open-meteo.test")
        XCTAssertEqual(queryItems["temperature_unit"] ?? nil, "fahrenheit")
        XCTAssertEqual(queryItems["timezone"] ?? nil, "auto")
        XCTAssertEqual(queryItems["forecast_days"] ?? nil, "3")
        XCTAssertEqual(snapshot.currentTemperature.value, 76.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.conditionDescription, "Rain")
        XCTAssertEqual(snapshot.symbolName, "cloud.rain.fill")
        XCTAssertEqual(try XCTUnwrap(snapshot.highTemperature).value, 82.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.lowTemperature).value, 58.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.hourlyForecast.count, 2)
        XCTAssertEqual(snapshot.hourlyForecast[1].precipitationChance, 0.45, accuracy: 0.001)
        XCTAssertEqual(snapshot.hourlyForecast[1].precipitationDescription, "rain")
        XCTAssertEqual(snapshot.dailyForecast.count, 2)
        XCTAssertEqual(try XCTUnwrap(snapshot.dailyForecast[0].precipitationChance), 0.45, accuracy: 0.001)
        XCTAssertEqual(snapshot.attributionURL, URL(string: "https://open-meteo.com/"))
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

    func testRefreshForHomeVisitReloadsAfterFirstLoad() async {
        var loadCount = 0
        let viewModel = HomeWeatherViewModel {
            loadCount += 1
            return Self.snapshot(current: Double(70 + loadCount))
        }

        await viewModel.loadIfNeeded()
        await viewModel.refreshForHomeVisit()

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.displayData.currentTemperatureText, "72°")
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

    func testCancelledRefreshKeepsSnapshotWithoutWeatherError() async {
        let now = Self.date("2026-07-01T16:00:00Z")
        var responses: [Result<HomeWeatherSnapshot, Error>] = [
            .success(Self.snapshot(current: 74, fetchedAt: now)),
            .failure(CancellationError())
        ]
        let viewModel = HomeWeatherViewModel(now: { now }) {
            try responses.removeFirst().get()
        }

        await viewModel.loadIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.displayData.currentTemperatureText, "74°")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.displayData.isStale)
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

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        json: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.open-meteo.test")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(json.utf8)
        )
    }
}

private final class MockCoordinateWeatherProvider: CoordinateWeatherSnapshotLoading {
    private let result: Result<HomeWeatherSnapshot, Error>
    private(set) var requestCount = 0

    init(result: Result<HomeWeatherSnapshot, Error>) {
        self.result = result
    }

    func fetchSnapshot(
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> HomeWeatherSnapshot {
        requestCount += 1
        return try result.get()
    }
}

private final class HangingCoordinateWeatherProvider: CoordinateWeatherSnapshotLoading {
    private(set) var requestCount = 0

    func fetchSnapshot(
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> HomeWeatherSnapshot {
        requestCount += 1
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
}

private final class MockWeatherURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
