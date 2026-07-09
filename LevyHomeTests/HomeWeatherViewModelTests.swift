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
            tertiaryWeatherProvider: nil,
            now: { now },
            fallbackStartDelay: .milliseconds(1)
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
            tertiaryWeatherProvider: nil,
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

    func testHomeWeatherServiceUsesTertiaryProviderWhenPrimaryAndFallbackFail() async throws {
        let now = Self.date("2026-07-01T16:00:00Z")
        let tertiarySnapshot = Self.snapshot(current: 83, condition: "Sunny", fetchedAt: now)
        let primaryProvider = MockCoordinateWeatherProvider(
            result: .failure(HomeWeatherServiceError.homeLocationUnavailable)
        )
        let fallbackProvider = MockCoordinateWeatherProvider(
            result: .failure(OpenMeteoHomeWeatherProviderError.invalidResponse)
        )
        let tertiaryProvider = MockCoordinateWeatherProvider(result: .success(tertiarySnapshot))
        let service = HomeWeatherService(
            homeLocationProvider: StaticHomeLocationProvider(latitude: 39.5, longitude: -105),
            primaryWeatherProvider: primaryProvider,
            fallbackWeatherProvider: fallbackProvider,
            tertiaryWeatherProvider: tertiaryProvider,
            now: { now },
            fallbackStartDelay: .milliseconds(1),
            tertiaryStartDelay: .milliseconds(1)
        )

        let snapshot = try await service.fetchSnapshot()

        XCTAssertEqual(snapshot.currentTemperature, tertiarySnapshot.currentTemperature)
        XCTAssertEqual(snapshot.conditionDescription, "Sunny")
        XCTAssertEqual(tertiaryProvider.requestCount, 1)
    }

    func testHomeWeatherServicePrefersFallbackProviderBeforeTertiaryProvider() async throws {
        let now = Self.date("2026-07-01T16:00:00Z")
        let fallbackSnapshot = Self.snapshot(current: 85, high: 91, low: 59, condition: "Open-Meteo", fetchedAt: now)
        let tertiarySnapshot = Self.snapshot(current: 73, high: 59, low: 59, condition: "NWS Tonight", fetchedAt: now)
        let primaryProvider = MockCoordinateWeatherProvider(
            result: .failure(HomeWeatherServiceError.homeLocationUnavailable)
        )
        let fallbackProvider = DelayedCoordinateWeatherProvider(
            delay: .milliseconds(25),
            result: .success(fallbackSnapshot)
        )
        let tertiaryProvider = MockCoordinateWeatherProvider(result: .success(tertiarySnapshot))
        let service = HomeWeatherService(
            homeLocationProvider: StaticHomeLocationProvider(latitude: 39.5, longitude: -105),
            primaryWeatherProvider: primaryProvider,
            fallbackWeatherProvider: fallbackProvider,
            tertiaryWeatherProvider: tertiaryProvider,
            now: { now },
            fallbackStartDelay: .milliseconds(1),
            tertiaryStartDelay: .milliseconds(150)
        )

        let snapshot = try await service.fetchSnapshot()

        XCTAssertEqual(snapshot.conditionDescription, "Open-Meteo")
        XCTAssertEqual(snapshot.currentTemperature.value, 85, accuracy: 0.001)
        XCTAssertEqual(fallbackProvider.requestCount, 1)
        XCTAssertEqual(tertiaryProvider.requestCount, 0)
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
            tertiaryWeatherProvider: nil,
            now: { now },
            providerTimeout: .milliseconds(10),
            fallbackStartDelay: .milliseconds(20)
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

    func testNationalWeatherServiceProviderBuildsForecastSnapshot() async throws {
        let now = Self.date("2026-07-01T16:00:00Z")
        var capturedRequests: [URLRequest] = []
        MockWeatherURLProtocol.requestHandler = { request in
            capturedRequests.append(request)

            switch request.url?.path {
            case "/points/39.5388,-105.0305":
                return Self.response(
                    for: request,
                    json: """
                    {
                      "properties": {
                        "forecast": "https://api.weather.test/gridpoints/BOU/61,53/forecast",
                        "forecastHourly": "https://api.weather.test/gridpoints/BOU/61,53/forecast/hourly"
                      }
                    }
                    """
                )
            case "/gridpoints/BOU/61,53/forecast/hourly":
                return Self.response(
                    for: request,
                    json: """
                    {
                      "properties": {
                        "periods": [
                          {
                            "startTime": "2026-07-01T10:00:00-06:00",
                            "isDaytime": true,
                            "temperature": 77,
                            "temperatureUnit": "F",
                            "probabilityOfPrecipitation": { "value": 20 },
                            "shortForecast": "Areas Of Smoke"
                          },
                          {
                            "startTime": "2026-07-01T11:00:00-06:00",
                            "isDaytime": true,
                            "temperature": 80,
                            "temperatureUnit": "F",
                            "probabilityOfPrecipitation": { "value": 35 },
                            "shortForecast": "Slight Chance Rain Showers"
                          }
                        ]
                      }
                    }
                    """
                )
            case "/gridpoints/BOU/61,53/forecast":
                return Self.response(
                    for: request,
                    json: """
                    {
                      "properties": {
                        "periods": [
                          {
                            "startTime": "2026-07-01T06:00:00-06:00",
                            "isDaytime": true,
                            "temperature": 84,
                            "temperatureUnit": "F",
                            "probabilityOfPrecipitation": { "value": 35 },
                            "shortForecast": "Slight Chance Rain Showers"
                          },
                          {
                            "startTime": "2026-07-01T18:00:00-06:00",
                            "isDaytime": false,
                            "temperature": 56,
                            "temperatureUnit": "F",
                            "probabilityOfPrecipitation": { "value": 10 },
                            "shortForecast": "Partly Cloudy"
                          }
                        ]
                      }
                    }
                    """
                )
            default:
                return Self.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer { MockWeatherURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockWeatherURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let provider = NationalWeatherServiceHomeWeatherProvider(
            baseURL: URL(string: "https://api.weather.test")!,
            session: session
        )

        let snapshot = try await provider.fetchSnapshot(
            for: CLLocation(latitude: 39.5388289, longitude: -105.0305231),
            fetchedAt: now
        )

        XCTAssertEqual(capturedRequests.first?.url?.path, "/points/39.5388,-105.0305")
        XCTAssertEqual(capturedRequests.first?.value(forHTTPHeaderField: "User-Agent"), "LevyHome/1.0")
        XCTAssertEqual(snapshot.currentTemperature.value, 77, accuracy: 0.001)
        XCTAssertEqual(snapshot.conditionDescription, "Areas Of Smoke")
        XCTAssertEqual(snapshot.symbolName, "sun.haze.fill")
        XCTAssertEqual(snapshot.hourlyForecast.count, 2)
        XCTAssertEqual(snapshot.hourlyForecast[1].precipitationChance, 0.35, accuracy: 0.001)
        XCTAssertEqual(snapshot.hourlyForecast[1].precipitationDescription, "showers")
        XCTAssertEqual(try XCTUnwrap(snapshot.highTemperature).value, 84, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.lowTemperature).value, 56, accuracy: 0.001)
        XCTAssertEqual(snapshot.attributionURL, URL(string: "https://www.weather.gov/"))
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

        XCTAssertEqual(viewModel.displayData.highLowTemperatureText, "91°/52°")
        XCTAssertEqual(viewModel.expandedData.chart.xAxisLabels.map(\.label), ["8 AM", "12 PM", "4 PM", "8 PM"])
        XCTAssertEqual(viewModel.expandedData.chart.yAxisValues.first, 89)
        XCTAssertEqual(viewModel.expandedData.chart.yAxisValues.last, 60)
        XCTAssertEqual(viewModel.expandedData.precipitationSummary, "Chance of light rain in the afternoon.")
        XCTAssertEqual(viewModel.expandedData.tomorrow.highText, "90°")
        XCTAssertEqual(viewModel.expandedData.tomorrow.lowText, "65°")
        XCTAssertEqual(viewModel.expandedData.tomorrow.averageText, "81°")
        XCTAssertEqual(viewModel.expandedData.tomorrow.precipitationChanceText, "35%")
    }

    func testExpandedChartUsesNextAvailableDaytimeWindowWhenTodayHasNoLineData() async {
        let now = Self.date("2026-07-04T23:30:00Z")
        let viewModel = HomeWeatherViewModel(now: { now }, calendar: Self.utcCalendar) {
            Self.snapshot(
                current: 72,
                high: 59,
                low: 59,
                hourlyForecast: [
                    Self.hourly("2026-07-04T23:00:00Z", temperature: 71),
                    Self.hourly("2026-07-05T06:00:00Z", temperature: 65),
                    Self.hourly("2026-07-05T09:00:00Z", temperature: 72),
                    Self.hourly("2026-07-05T12:00:00Z", temperature: 86),
                    Self.hourly("2026-07-05T15:00:00Z", temperature: 92),
                    Self.hourly("2026-07-05T18:00:00Z", temperature: 88),
                    Self.hourly("2026-07-05T21:00:00Z", temperature: 79)
                ],
                dailyForecast: [
                    HomeWeatherDailyForecast(
                        date: Self.date("2026-07-04T00:00:00Z"),
                        highTemperature: Measurement(value: 86, unit: UnitTemperature.fahrenheit),
                        lowTemperature: Measurement(value: 59, unit: UnitTemperature.fahrenheit),
                        precipitationChance: 0.1
                    ),
                    HomeWeatherDailyForecast(
                        date: Self.date("2026-07-05T00:00:00Z"),
                        highTemperature: Measurement(value: 93, unit: UnitTemperature.fahrenheit),
                        lowTemperature: Measurement(value: 64, unit: UnitTemperature.fahrenheit),
                        precipitationChance: 0.05
                    )
                ]
            )
        }

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.displayData.highLowTemperatureText, "86°/59°")
        XCTAssertGreaterThan(viewModel.expandedData.chart.points.count, 1)
        XCTAssertEqual(viewModel.expandedData.chart.points.map { Int($0.temperature.rounded()) }, [65, 72, 86, 92, 88, 79])
    }

    func testExpandedChartAddsClusteredPrecipitationMarkers() async {
        let now = Self.date("2026-07-01T08:00:00Z")
        let viewModel = HomeWeatherViewModel(now: { now }, calendar: Self.utcCalendar) {
            Self.snapshot(
                current: 72,
                hourlyForecast: [
                    Self.hourly("2026-07-01T06:00:00Z", temperature: 65),
                    Self.hourly("2026-07-01T09:00:00Z", temperature: 70, condition: "Rain", chance: 0.45, precipitation: "rain"),
                    Self.hourly("2026-07-01T10:00:00Z", temperature: 71, condition: "Rain", chance: 0.38, precipitation: "rain"),
                    Self.hourly("2026-07-01T11:00:00Z", temperature: 73, condition: "Clear"),
                    Self.hourly("2026-07-01T14:00:00Z", temperature: 82, condition: "Thunderstorm", chance: 0.75, precipitation: "thunderstorm"),
                    Self.hourly("2026-07-01T15:00:00Z", temperature: 80, condition: "Thunderstorm", chance: 0.68, precipitation: "thunderstorm"),
                    Self.hourly("2026-07-01T16:00:00Z", temperature: 78, condition: "Thunderstorm", chance: 0.52, precipitation: "thunderstorm"),
                    Self.hourly("2026-07-01T18:00:00Z", temperature: 76, condition: "Clear"),
                    Self.hourly("2026-07-01T20:00:00Z", temperature: 71)
                ]
            )
        }

        await viewModel.loadIfNeeded()

        let markers = viewModel.expandedData.chart.markers
        XCTAssertEqual(markers.map(\.systemImage), [
            "cloud.drizzle.fill",
            "sun.max.fill",
            "cloud.bolt.rain.fill",
            "sun.max.fill"
        ])
        XCTAssertEqual(markers.map { $0.isPrecipitationStart }, [true, false, true, false])
        XCTAssertEqual(markers.map { String(format: "%.4f", $0.position) }, ["0.1875", "0.3125", "0.5000", "0.7500"])
    }

    func testExpandedChartUsesNighttimeEndingMarkerAfterSunset() async {
        let now = Self.date("2026-01-05T18:00:00Z")
        let viewModel = HomeWeatherViewModel(now: { now }, calendar: Self.utcCalendar) {
            Self.snapshot(
                current: 34,
                hourlyForecast: [
                    Self.hourly("2026-01-05T18:00:00Z", temperature: 34),
                    Self.hourly("2026-01-05T20:00:00Z", temperature: 31, condition: "Snow", chance: 0.62, precipitation: "snow"),
                    Self.hourly("2026-01-05T21:00:00Z", temperature: 29, condition: "Clear"),
                    Self.hourly("2026-01-05T22:00:00Z", temperature: 27, condition: "Clear")
                ]
            )
        }

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.expandedData.chart.markers.map(\.systemImage), [
            "cloud.snow.fill",
            "moon.stars.fill"
        ])
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

private final class DelayedCoordinateWeatherProvider: CoordinateWeatherSnapshotLoading {
    private let delay: Duration
    private let result: Result<HomeWeatherSnapshot, Error>
    private(set) var requestCount = 0

    init(
        delay: Duration,
        result: Result<HomeWeatherSnapshot, Error>
    ) {
        self.delay = delay
        self.result = result
    }

    func fetchSnapshot(
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> HomeWeatherSnapshot {
        requestCount += 1
        try await Task.sleep(for: delay)
        return try result.get()
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
