struct OpenMeteoWeatherCode {
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
