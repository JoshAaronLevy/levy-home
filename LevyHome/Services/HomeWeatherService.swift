import CoreLocation
import Foundation
import WeatherKit

protocol HomeWeatherServicing {
    func fetchSnapshot() async throws -> HomeWeatherSnapshot
}

protocol HomeLocationProviding {
    func location() async throws -> CLLocation
}

protocol CoordinateWeatherSnapshotLoading {
    func fetchSnapshot(
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> HomeWeatherSnapshot
}

private struct HomeWeatherProviderAttempt {
    let name: String
    let provider: CoordinateWeatherSnapshotLoading
    let startDelay: Duration?
}

private struct HomeWeatherProviderFailure {
    let providerName: String
    let error: Error
}

private enum HomeWeatherProviderAttemptResult {
    case success(providerName: String, snapshot: HomeWeatherSnapshot)
    case failure(HomeWeatherProviderFailure)
}

struct StaticHomeLocationProvider: HomeLocationProviding {
    static let levyHome = StaticHomeLocationProvider(
        latitude: 39.5388289,
        longitude: -105.0305231
    )

    init(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees
    ) {
        self.location = CLLocation(latitude: latitude, longitude: longitude)
    }

    private let location: CLLocation

    func location() async throws -> CLLocation { location }
}

enum HomeWeatherServiceError: LocalizedError {
    case homeLocationUnavailable
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .homeLocationUnavailable:
            return "Home weather location is unavailable."
        case .requestTimedOut:
            return "Home weather request timed out."
        }
    }
}

final class HomeWeatherService: HomeWeatherServicing {
    private let homeLocationProvider: HomeLocationProviding
    private let primaryWeatherProvider: CoordinateWeatherSnapshotLoading
    private let fallbackWeatherProvider: CoordinateWeatherSnapshotLoading?
    private let tertiaryWeatherProvider: CoordinateWeatherSnapshotLoading?
    private let now: () -> Date
    private let providerTimeout: Duration
    private let fallbackStartDelay: Duration
    private let appLogStore: AppLogStore?

    init(
        homeLocationProvider: HomeLocationProviding = StaticHomeLocationProvider.levyHome,
        primaryWeatherProvider: CoordinateWeatherSnapshotLoading = WeatherKitHomeWeatherProvider(),
        fallbackWeatherProvider: CoordinateWeatherSnapshotLoading? = OpenMeteoHomeWeatherProvider(),
        tertiaryWeatherProvider: CoordinateWeatherSnapshotLoading? = NationalWeatherServiceHomeWeatherProvider(),
        now: @escaping () -> Date = Date.init,
        providerTimeout: Duration = .seconds(8),
        fallbackStartDelay: Duration = .seconds(1),
        appLogStore: AppLogStore? = nil
    ) {
        self.homeLocationProvider = homeLocationProvider
        self.primaryWeatherProvider = primaryWeatherProvider
        self.fallbackWeatherProvider = fallbackWeatherProvider
        self.tertiaryWeatherProvider = tertiaryWeatherProvider
        self.now = now
        self.providerTimeout = providerTimeout
        self.fallbackStartDelay = fallbackStartDelay
        self.appLogStore = appLogStore
    }

    func fetchSnapshot() async throws -> HomeWeatherSnapshot {
        do {
            let location = try await homeLocationProvider.location()
            let fetchedAt = now()
            let attempts = weatherProviderAttempts

            appLogStore?.record(
                level: .info,
                category: "Weather",
                title: "Fetching Home weather",
                detail: "Providers: \(attempts.map(\.name).joined(separator: ", "))"
            )

            let result = try await fetchFirstSuccessfulSnapshot(
                attempts: attempts,
                for: location,
                fetchedAt: fetchedAt
            )

            appLogStore?.record(
                level: .success,
                category: "Weather",
                title: "Loaded Home weather",
                detail: "\(result.providerName): \(Self.temperatureText(result.snapshot.currentTemperature)), \(result.snapshot.conditionDescription)"
            )

            return result.snapshot
        } catch {
            if error.isTaskCancellation {
                appLogStore?.record(
                    level: .info,
                    category: "Weather",
                    title: "Cancelled Home weather refresh",
                    detail: nil
                )
                throw error
            }

            appLogStore?.record(
                level: .error,
                category: "Weather",
                title: "Home weather unavailable",
                detail: error.localizedDescription
            )
            throw error
        }
    }

    private var weatherProviderAttempts: [HomeWeatherProviderAttempt] {
        var attempts = [
            HomeWeatherProviderAttempt(
                name: "WeatherKit",
                provider: primaryWeatherProvider,
                startDelay: nil
            )
        ]

        if let fallbackWeatherProvider {
            attempts.append(
                HomeWeatherProviderAttempt(
                    name: "Open-Meteo",
                    provider: fallbackWeatherProvider,
                    startDelay: fallbackStartDelay
                )
            )
        }

        if let tertiaryWeatherProvider {
            attempts.append(
                HomeWeatherProviderAttempt(
                    name: "National Weather Service",
                    provider: tertiaryWeatherProvider,
                    startDelay: fallbackStartDelay
                )
            )
        }

        return attempts
    }

    private func fetchFirstSuccessfulSnapshot(
        attempts: [HomeWeatherProviderAttempt],
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> (providerName: String, snapshot: HomeWeatherSnapshot) {
        let providerTimeout = providerTimeout
        var failures: [HomeWeatherProviderFailure] = []

        return try await withThrowingTaskGroup(of: HomeWeatherProviderAttemptResult.self) { group in
            defer { group.cancelAll() }

            for attempt in attempts {
                group.addTask {
                    do {
                        if let startDelay = attempt.startDelay {
                            try await Task.sleep(for: startDelay)
                        }

                        let snapshot = try await Self.fetchSnapshot(
                            using: attempt.provider,
                            for: location,
                            fetchedAt: fetchedAt,
                            timeout: providerTimeout
                        )

                        return .success(providerName: attempt.name, snapshot: snapshot)
                    } catch {
                        return .failure(
                            HomeWeatherProviderFailure(
                                providerName: attempt.name,
                                error: error
                            )
                        )
                    }
                }
            }

            while let result = try await group.next() {
                switch result {
                case .success(let providerName, let snapshot):
                    return (providerName, snapshot)
                case .failure(let failure):
                    if failure.error.isTaskCancellation {
                        throw failure.error
                    }

                    failures.append(failure)
                    recordProviderFailure(failure)
                }
            }

            throw failures.last?.error ?? HomeWeatherServiceError.requestTimedOut
        }
    }

    private func recordProviderFailure(_ failure: HomeWeatherProviderFailure) {
        appLogStore?.record(
            level: .warning,
            category: "Weather",
            title: "\(failure.providerName) weather failed",
            detail: failure.error.localizedDescription
        )
    }

    private static func fetchSnapshot(
        using provider: CoordinateWeatherSnapshotLoading,
        for location: CLLocation,
        fetchedAt: Date,
        timeout: Duration
    ) async throws -> HomeWeatherSnapshot {
        return try await withThrowingTaskGroup(of: HomeWeatherSnapshot.self) { group in
            defer { group.cancelAll() }

            group.addTask {
                try await provider.fetchSnapshot(
                    for: location,
                    fetchedAt: fetchedAt
                )
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw HomeWeatherServiceError.requestTimedOut
            }

            guard let snapshot = try await group.next() else {
                throw HomeWeatherServiceError.requestTimedOut
            }

            return snapshot
        }
    }

    private static func temperatureText(_ temperature: Measurement<UnitTemperature>) -> String {
        "\(Int(temperature.converted(to: .fahrenheit).value.rounded()))°"
    }
}

final class WeatherKitHomeWeatherProvider: CoordinateWeatherSnapshotLoading {
    private let weatherService: WeatherService

    init(weatherService: WeatherService = .shared) {
        self.weatherService = weatherService
    }

    func fetchSnapshot(
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> HomeWeatherSnapshot {
        let weather = try await weatherService.weather(for: location)
        let attribution = try? await weatherService.attribution
        let dailyWeather = weather.dailyForecast.forecast.first
        let hourlyForecast = weather.hourlyForecast.forecast.map { hour in
            HomeWeatherForecastPoint(
                date: hour.date,
                temperature: hour.temperature,
                conditionDescription: hour.condition.description,
                precipitationChance: hour.precipitationChance,
                precipitationDescription: hour.precipitation.description
            )
        }
        let dailyForecast = weather.dailyForecast.forecast.map { day in
            HomeWeatherDailyForecast(
                date: day.date,
                highTemperature: day.highTemperature,
                lowTemperature: day.lowTemperature,
                precipitationChance: day.precipitationChance
            )
        }

        return HomeWeatherSnapshot(
            currentTemperature: weather.currentWeather.temperature,
            highTemperature: dailyWeather?.highTemperature,
            lowTemperature: dailyWeather?.lowTemperature,
            conditionDescription: weather.currentWeather.condition.description,
            symbolName: weather.currentWeather.symbolName,
            attributionURL: attribution?.legalPageURL,
            fetchedAt: fetchedAt,
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast
        )
    }
}

enum OpenMeteoHomeWeatherProviderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingCurrentWeather

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Open-Meteo weather request could not be built."
        case .invalidResponse:
            return "Open-Meteo weather response was not successful."
        case .missingCurrentWeather:
            return "Open-Meteo weather response did not include current weather."
        }
    }
}

final class OpenMeteoHomeWeatherProvider: CoordinateWeatherSnapshotLoading {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        baseURL: URL = URL(string: "https://api.open-meteo.com/v1/forecast")!,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
    }

    func fetchSnapshot(
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> HomeWeatherSnapshot {
        let url = try forecastURL(for: location)
        let (data, response) = try await session.data(from: url)

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw OpenMeteoHomeWeatherProviderError.invalidResponse
        }

        let forecast = try decoder.decode(OpenMeteoForecastResponse.self, from: data)
        return try forecast.snapshot(fetchedAt: fetchedAt)
    }

    private func forecastURL(for location: CLLocation) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw OpenMeteoHomeWeatherProviderError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,precipitation"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "3")
        ]

        guard let url = components.url else {
            throw OpenMeteoHomeWeatherProviderError.invalidURL
        }

        return url
    }
}

enum NationalWeatherServiceHomeWeatherProviderError: LocalizedError {
    case invalidURL
    case invalidResponse(Int)
    case missingForecast

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "National Weather Service request could not be built."
        case .invalidResponse(let statusCode):
            return "National Weather Service returned HTTP \(statusCode)."
        case .missingForecast:
            return "National Weather Service response did not include a usable forecast."
        }
    }
}

final class NationalWeatherServiceHomeWeatherProvider: CoordinateWeatherSnapshotLoading {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let userAgent: String

    init(
        baseURL: URL = URL(string: "https://api.weather.gov")!,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        userAgent: String = "LevyHome/1.0"
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
        self.userAgent = userAgent
        self.decoder.dateDecodingStrategy = .custom { decoder in
            try Self.decodeDate(from: decoder)
        }
    }

    func fetchSnapshot(
        for location: CLLocation,
        fetchedAt: Date
    ) async throws -> HomeWeatherSnapshot {
        let point: NationalWeatherServicePointResponse = try await fetch(url: pointURL(for: location))

        async let hourlyForecast: NationalWeatherServiceForecastResponse = fetch(url: point.properties.forecastHourly)
        async let dailyForecast: NationalWeatherServiceForecastResponse = fetch(url: point.properties.forecast)

        return try await Self.snapshot(
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast,
            fetchedAt: fetchedAt
        )
    }

    private func pointURL(for location: CLLocation) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NationalWeatherServiceHomeWeatherProviderError.invalidURL
        }

        let latitude = Self.coordinateText(location.coordinate.latitude)
        let longitude = Self.coordinateText(location.coordinate.longitude)
        components.path = "/points/\(latitude),\(longitude)"

        guard let url = components.url else {
            throw NationalWeatherServiceHomeWeatherProviderError.invalidURL
        }

        return url
    }

    private func fetch<Response: Decodable>(url: URL) async throws -> Response {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NationalWeatherServiceHomeWeatherProviderError.invalidResponse(-1)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NationalWeatherServiceHomeWeatherProviderError.invalidResponse(httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }

    private static func snapshot(
        hourlyForecast: NationalWeatherServiceForecastResponse,
        dailyForecast: NationalWeatherServiceForecastResponse,
        fetchedAt: Date
    ) throws -> HomeWeatherSnapshot {
        let hourlyPoints = hourlyForecast.properties.periods.prefix(72).map(\.forecastPoint)

        guard let currentPeriod = hourlyForecast.properties.periods.first,
              let currentPoint = hourlyPoints.first
        else {
            throw NationalWeatherServiceHomeWeatherProviderError.missingForecast
        }

        let dailyForecasts = dailyForecast.properties.periods.dailyForecasts()
        let currentDailyForecast = dailyForecasts.first

        return HomeWeatherSnapshot(
            currentTemperature: currentPoint.temperature,
            highTemperature: currentDailyForecast?.highTemperature,
            lowTemperature: currentDailyForecast?.lowTemperature,
            conditionDescription: currentPoint.conditionDescription,
            symbolName: Self.symbolName(
                for: currentPoint.conditionDescription,
                isDaytime: currentPeriod.isDaytime
            ),
            attributionURL: URL(string: "https://www.weather.gov/"),
            fetchedAt: fetchedAt,
            hourlyForecast: Array(hourlyPoints),
            dailyForecast: dailyForecasts
        )
    }

    private static func coordinateText(_ value: CLLocationDegrees) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let date = iso8601DateFormatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid National Weather Service date: \(value)"
        )
    }

    private static let iso8601DateFormatter = ISO8601DateFormatter()

    private static func symbolName(for forecast: String, isDaytime: Bool) -> String {
        let normalizedForecast = forecast.lowercased()

        if normalizedForecast.contains("thunder") {
            return "cloud.bolt.rain.fill"
        }

        if normalizedForecast.contains("snow") {
            return "cloud.snow.fill"
        }

        if normalizedForecast.contains("rain") || normalizedForecast.contains("shower") {
            return "cloud.rain.fill"
        }

        if normalizedForecast.contains("drizzle") {
            return "cloud.drizzle.fill"
        }

        if normalizedForecast.contains("fog") {
            return "cloud.fog.fill"
        }

        if normalizedForecast.contains("smoke") || normalizedForecast.contains("haze") {
            return "sun.haze.fill"
        }

        if normalizedForecast.contains("cloud") || normalizedForecast.contains("overcast") {
            return normalizedForecast.contains("partly") ? "cloud.sun.fill" : "cloud.fill"
        }

        if normalizedForecast.contains("clear") || normalizedForecast.contains("sunny") {
            return isDaytime ? "sun.max.fill" : "moon.stars.fill"
        }

        return "cloud.sun.fill"
    }
}

private struct NationalWeatherServicePointResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let forecast: URL
        let forecastHourly: URL
    }
}

private struct NationalWeatherServiceForecastResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let periods: [Period]
    }

    struct Period: Decodable {
        let startTime: Date
        let isDaytime: Bool
        let temperature: Double
        let temperatureUnit: String
        let probabilityOfPrecipitation: Probability?
        let shortForecast: String

        var forecastPoint: HomeWeatherForecastPoint {
            HomeWeatherForecastPoint(
                date: startTime,
                temperature: Measurement(value: fahrenheitTemperature, unit: UnitTemperature.fahrenheit),
                conditionDescription: shortForecast,
                precipitationChance: precipitationChance,
                precipitationDescription: precipitationDescription
            )
        }

        private var fahrenheitTemperature: Double {
            if temperatureUnit.localizedCaseInsensitiveCompare("C") == .orderedSame {
                return Measurement(value: temperature, unit: UnitTemperature.celsius)
                    .converted(to: .fahrenheit)
                    .value
            }

            return temperature
        }

        private var precipitationChance: Double {
            guard let value = probabilityOfPrecipitation?.value else {
                return 0
            }

            return min(max(value / 100, 0), 1)
        }

        private var precipitationDescription: String {
            let normalizedForecast = shortForecast.lowercased()

            if normalizedForecast.contains("thunder") {
                return "thunderstorm"
            }

            if normalizedForecast.contains("snow") {
                return "snow"
            }

            if normalizedForecast.contains("shower") {
                return "showers"
            }

            if normalizedForecast.contains("rain") || normalizedForecast.contains("drizzle") {
                return "rain"
            }

            return precipitationChance > 0 ? "precipitation" : "none"
        }
    }

    struct Probability: Decodable {
        let value: Double?
    }
}

private extension Array where Element == NationalWeatherServiceForecastResponse.Period {
    func dailyForecasts() -> [HomeWeatherDailyForecast] {
        let calendar = Calendar.current
        let groupedPeriods = Dictionary(grouping: self) { period in
            calendar.startOfDay(for: period.startTime)
        }

        return groupedPeriods.keys.sorted().map { date in
            let periods = groupedPeriods[date] ?? []
            let temperatures = periods.map(\.forecastPoint.temperature)
            let precipitationChance = periods
                .map(\.forecastPoint.precipitationChance)
                .max()

            return HomeWeatherDailyForecast(
                date: date,
                highTemperature: temperatures.max { first, second in
                    first.converted(to: .fahrenheit).value < second.converted(to: .fahrenheit).value
                },
                lowTemperature: temperatures.min { first, second in
                    first.converted(to: .fahrenheit).value < second.converted(to: .fahrenheit).value
                },
                precipitationChance: precipitationChance
            )
        }
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    let timezone: String?
    let current: Current?
    let hourly: Hourly?
    let daily: Daily?

    func snapshot(fetchedAt: Date) throws -> HomeWeatherSnapshot {
        guard let currentTemperature = current?.temperature else {
            throw OpenMeteoHomeWeatherProviderError.missingCurrentWeather
        }

        let timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let currentCondition = OpenMeteoWeatherCode(current?.weatherCode)
        let dailyForecast = daily?.forecast(timeZone: timeZone) ?? []
        let hourlyForecast = hourly?.forecast(timeZone: timeZone) ?? []
        let todayForecast = dailyForecast.first

        return HomeWeatherSnapshot(
            currentTemperature: Measurement(value: currentTemperature, unit: UnitTemperature.fahrenheit),
            highTemperature: todayForecast?.highTemperature,
            lowTemperature: todayForecast?.lowTemperature,
            conditionDescription: currentCondition.description,
            symbolName: currentCondition.symbolName,
            attributionURL: URL(string: "https://open-meteo.com/"),
            fetchedAt: fetchedAt,
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast
        )
    }

    struct Current: Decodable {
        let temperature: Double?
        let weatherCode: Int?
        let precipitation: Double?

        private enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitation
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperatures: [Double]
        let precipitationProbabilities: [Double]?
        let precipitationAmounts: [Double]?
        let weatherCodes: [Int]?

        private enum CodingKeys: String, CodingKey {
            case time
            case temperatures = "temperature_2m"
            case precipitationProbabilities = "precipitation_probability"
            case precipitationAmounts = "precipitation"
            case weatherCodes = "weather_code"
        }

        func forecast(timeZone: TimeZone) -> [HomeWeatherForecastPoint] {
            let parser = OpenMeteoDateParser(timeZone: timeZone)

            return time.indices.compactMap { index in
                guard
                    temperatures.indices.contains(index),
                    let date = parser.dateTime(from: time[index])
                else {
                    return nil
                }

                let code = weatherCodes[safe: index]
                let condition = OpenMeteoWeatherCode(code)
                let precipitationAmount = precipitationAmounts[safe: index] ?? 0

                return HomeWeatherForecastPoint(
                    date: date,
                    temperature: Measurement(value: temperatures[index], unit: UnitTemperature.fahrenheit),
                    conditionDescription: condition.description,
                    precipitationChance: Self.chance(fromPercent: precipitationProbabilities[safe: index]),
                    precipitationDescription: condition.precipitationDescription(precipitationAmount: precipitationAmount)
                )
            }
        }

        private static func chance(fromPercent value: Double?) -> Double {
            guard let value else {
                return 0
            }

            return min(max(value / 100, 0), 1)
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let highTemperatures: [Double]?
        let lowTemperatures: [Double]?
        let precipitationProbabilities: [Double]?

        private enum CodingKeys: String, CodingKey {
            case time
            case highTemperatures = "temperature_2m_max"
            case lowTemperatures = "temperature_2m_min"
            case precipitationProbabilities = "precipitation_probability_max"
        }

        func forecast(timeZone: TimeZone) -> [HomeWeatherDailyForecast] {
            let parser = OpenMeteoDateParser(timeZone: timeZone)

            return time.indices.compactMap { index in
                guard let date = parser.date(from: time[index]) else {
                    return nil
                }

                return HomeWeatherDailyForecast(
                    date: date,
                    highTemperature: highTemperatures[safe: index].map {
                        Measurement(value: $0, unit: UnitTemperature.fahrenheit)
                    },
                    lowTemperature: lowTemperatures[safe: index].map {
                        Measurement(value: $0, unit: UnitTemperature.fahrenheit)
                    },
                    precipitationChance: precipitationProbabilities[safe: index].map {
                        min(max($0 / 100, 0), 1)
                    }
                )
            }
        }
    }
}

private struct OpenMeteoDateParser {
    private let dateTimeFormatter: DateFormatter
    private let dateFormatter: DateFormatter

    init(timeZone: TimeZone) {
        dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateTimeFormatter.timeZone = timeZone
        dateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
    }

    func dateTime(from value: String) -> Date? {
        dateTimeFormatter.date(from: value)
    }

    func date(from value: String) -> Date? {
        dateFormatter.date(from: value)
    }
}

private struct OpenMeteoWeatherCode {
    let rawValue: Int?

    init(_ rawValue: Int?) {
        self.rawValue = rawValue
    }

    var description: String {
        switch rawValue {
        case 0:
            return "Clear"
        case 1:
            return "Mainly Clear"
        case 2:
            return "Partly Cloudy"
        case 3:
            return "Overcast"
        case 45, 48:
            return "Fog"
        case 51, 53, 55:
            return "Drizzle"
        case 56, 57:
            return "Freezing Drizzle"
        case 61, 63, 65:
            return "Rain"
        case 66, 67:
            return "Freezing Rain"
        case 71, 73, 75:
            return "Snow"
        case 77:
            return "Snow Grains"
        case 80, 81, 82:
            return "Rain Showers"
        case 85, 86:
            return "Snow Showers"
        case 95:
            return "Thunderstorm"
        case 96, 99:
            return "Thunderstorm With Hail"
        default:
            return "Forecast"
        }
    }

    var symbolName: String {
        switch rawValue {
        case 0, 1:
            return "sun.max.fill"
        case 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.sun.fill"
        }
    }

    func precipitationDescription(precipitationAmount: Double) -> String {
        switch rawValue {
        case 71, 73, 75, 77, 85, 86:
            return "snow"
        case 95, 96, 99:
            return "thunderstorm"
        case 51, 53, 55, 56, 57:
            return "drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return "rain"
        default:
            return precipitationAmount > 0 ? "precipitation" : "none"
        }
    }
}

private extension Optional where Wrapped: Collection, Wrapped.Index == Int {
    subscript(safe index: Int) -> Wrapped.Element? {
        guard let collection = self, collection.indices.contains(index) else {
            return nil
        }

        return collection[index]
    }
}
