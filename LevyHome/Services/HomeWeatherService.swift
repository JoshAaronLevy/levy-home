import CoreLocation
import Foundation
import WeatherKit

protocol HomeWeatherServicing {
    func fetchSnapshot() async throws -> HomeWeatherSnapshot
}

protocol HomeLocationProviding {
    func location() async throws -> CLLocation
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
    private let weatherService: WeatherService
    private let now: () -> Date

    init(
        homeLocationProvider: HomeLocationProviding = StaticHomeLocationProvider.levyHome,
        weatherService: WeatherService = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.homeLocationProvider = homeLocationProvider
        self.weatherService = weatherService
        self.now = now
    }

    func fetchSnapshot() async throws -> HomeWeatherSnapshot {
        let location = try await homeLocationProvider.location()
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
            fetchedAt: now(),
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast
        )
    }
}
