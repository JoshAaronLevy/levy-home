import Foundation

struct HomeWeatherForecastPoint: Equatable {
    let date: Date
    let temperature: Measurement<UnitTemperature>
    let conditionDescription: String
    let precipitationChance: Double
    let precipitationDescription: String
}

struct HomeWeatherDailyForecast: Equatable {
    let date: Date
    let highTemperature: Measurement<UnitTemperature>?
    let lowTemperature: Measurement<UnitTemperature>?
    let precipitationChance: Double?
}

struct HomeWeatherSnapshot: Equatable {
    let currentTemperature: Measurement<UnitTemperature>
    let highTemperature: Measurement<UnitTemperature>?
    let lowTemperature: Measurement<UnitTemperature>?
    let conditionDescription: String
    let symbolName: String
    let attributionURL: URL?
    let fetchedAt: Date
    let hourlyForecast: [HomeWeatherForecastPoint]
    let dailyForecast: [HomeWeatherDailyForecast]

    init(
        currentTemperature: Measurement<UnitTemperature>,
        highTemperature: Measurement<UnitTemperature>?,
        lowTemperature: Measurement<UnitTemperature>?,
        conditionDescription: String,
        symbolName: String,
        attributionURL: URL?,
        fetchedAt: Date,
        hourlyForecast: [HomeWeatherForecastPoint] = [],
        dailyForecast: [HomeWeatherDailyForecast] = []
    ) {
        self.currentTemperature = currentTemperature
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
        self.conditionDescription = conditionDescription
        self.symbolName = symbolName
        self.attributionURL = attributionURL
        self.fetchedAt = fetchedAt
        self.hourlyForecast = hourlyForecast
        self.dailyForecast = dailyForecast
    }
}
