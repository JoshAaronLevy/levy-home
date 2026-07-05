import CoreLocation
import Foundation
import WeatherKit

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
        let dailyWeather = dailyForecast.first { forecast in
            Calendar.current.isDate(forecast.date, inSameDayAs: fetchedAt)
        } ?? dailyForecast.first

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
