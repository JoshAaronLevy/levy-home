import CoreLocation
import Foundation

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
        let currentDailyForecast = dailyForecasts.first { forecast in
            Calendar.current.isDate(forecast.date, inSameDayAs: fetchedAt)
        } ?? dailyForecasts.first

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
