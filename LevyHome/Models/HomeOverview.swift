import Foundation

struct HomeOverview: Codable, Equatable {
    let garageStatus: GarageStatus
    let lightSummary: LightSummary
    let thermostatStatus: ThermostatStatus?
    let presence: [HomePresenceStatus]?
    let recentImportantEvent: LevyHomeEvent?
    let generatedAt: String?
    let isPartial: Bool?

    init(
        garageStatus: GarageStatus,
        lightSummary: LightSummary,
        thermostatStatus: ThermostatStatus? = nil,
        presence: [HomePresenceStatus]?,
        recentImportantEvent: LevyHomeEvent?,
        generatedAt: String?,
        isPartial: Bool?
    ) {
        self.garageStatus = garageStatus
        self.lightSummary = lightSummary
        self.thermostatStatus = thermostatStatus
        self.presence = presence
        self.recentImportantEvent = recentImportantEvent
        self.generatedAt = generatedAt
        self.isPartial = isPartial
    }
}

struct ThermostatStatus: Codable, Equatable {
    let currentTemperature: Double?
    let targetTemperatureLow: Double?
    let targetTemperatureHigh: Double?
    let lastUpdatedAt: String?
    let isStale: Bool?
}

struct HomePresenceStatus: Codable, Equatable, Identifiable {
    enum State: Codable, Equatable, Hashable {
        case home
        case away
        case unknown
        case unrecognized(String)

        var rawValue: String {
            switch self {
            case .home:
                return "home"
            case .away:
                return "away"
            case .unknown:
                return "unknown"
            case .unrecognized(let rawValue):
                return rawValue
            }
        }

        init(rawValue: String) {
            switch rawValue {
            case "home":
                self = .home
            case "away":
                self = .away
            case "unknown":
                self = .unknown
            default:
                self = .unrecognized(rawValue)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.init(rawValue: try container.decode(String.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    let person: String
    let state: State
    let entityId: String?
    let deviceName: String?
    let lastUpdatedAt: String?
    let isStale: Bool?

    var id: String {
        person.lowercased()
    }
}
