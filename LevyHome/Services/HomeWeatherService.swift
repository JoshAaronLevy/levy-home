import CoreLocation
import Foundation
import WeatherKit

protocol HomeWeatherServicing {
    func fetchSnapshot() async throws -> HomeWeatherSnapshot
}

protocol HomeLocationProviding {
    func location() async throws -> CLLocation
}

actor GeocodedHomeLocationProvider: HomeLocationProviding {
    private let addresses: [String]
    private let geocoder: CLGeocoder
    private var cachedLocation: CLLocation?

    init(
        addresses: [String] = [
            "9774 Bucknell Ct, Highlands Ranch, CO 80129",
            "9774 Bucknell Ct, Littleton, CO 80129"
        ],
        geocoder: CLGeocoder = CLGeocoder()
    ) {
        self.addresses = addresses
        self.geocoder = geocoder
    }

    func location() async throws -> CLLocation {
        if let cachedLocation {
            return cachedLocation
        }

        var lastError: Error?
        for address in addresses {
            do {
                let placemarks = try await geocoder.geocodeAddressString(address)
                if let location = placemarks.first?.location {
                    cachedLocation = location
                    return location
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? HomeWeatherServiceError.homeLocationUnavailable
    }
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
        homeLocationProvider: HomeLocationProviding = GeocodedHomeLocationProvider(),
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
