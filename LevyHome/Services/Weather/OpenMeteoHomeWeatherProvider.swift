import CoreLocation
import Foundation

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
        let todayForecast = dailyForecast.first { forecast in
            Calendar.current.isDate(forecast.date, inSameDayAs: fetchedAt)
        } ?? dailyForecast.first

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
