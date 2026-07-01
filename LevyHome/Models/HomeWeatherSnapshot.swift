import Foundation

struct HomeWeatherSnapshot: Equatable {
    let currentTemperature: Measurement<UnitTemperature>
    let highTemperature: Measurement<UnitTemperature>?
    let lowTemperature: Measurement<UnitTemperature>?
    let conditionDescription: String
    let symbolName: String
    let attributionURL: URL?
    let fetchedAt: Date
}
