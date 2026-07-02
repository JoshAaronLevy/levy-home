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

    var errorDescription: String? {
        switch self {
        case .homeLocationUnavailable:
            return "Home weather location is unavailable."
        }
    }
}

final class HomeWeatherService: HomeWeatherServicing {
    private let homeLocationProvider: HomeLocationProviding
    private let primaryWeatherProvider: CoordinateWeatherSnapshotLoading
    private let fallbackWeatherProvider: CoordinateWeatherSnapshotLoading?
    private let now: () -> Date

    init(
        homeLocationProvider: HomeLocationProviding = StaticHomeLocationProvider.levyHome,
        primaryWeatherProvider: CoordinateWeatherSnapshotLoading = WeatherKitHomeWeatherProvider(),
        fallbackWeatherProvider: CoordinateWeatherSnapshotLoading? = OpenMeteoHomeWeatherProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.homeLocationProvider = homeLocationProvider
        self.primaryWeatherProvider = primaryWeatherProvider
        self.fallbackWeatherProvider = fallbackWeatherProvider
        self.now = now
    }

    func fetchSnapshot() async throws -> HomeWeatherSnapshot {
        let location = try await homeLocationProvider.location()
        let fetchedAt = now()

        do {
            return try await primaryWeatherProvider.fetchSnapshot(
                for: location,
                fetchedAt: fetchedAt
            )
        } catch {
            guard !error.isTaskCancellation else {
                throw error
            }

            guard let fallbackWeatherProvider else {
                throw error
            }

            return try await fallbackWeatherProvider.fetchSnapshot(
                for: location,
                fetchedAt: fetchedAt
            )
        }
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
