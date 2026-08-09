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
    let minimumTemperature: Double?
    let maximumTemperature: Double?
    let temperatureStep: Double?
    let hvacAction: String?
    let lastUpdatedAt: String?
    let isStale: Bool?
}

struct ThermostatSetpointDraft: Equatable {
    static let minimumDelta = 7.0
    static let controlStep = 1.0

    private(set) var low: Double
    private(set) var high: Double
    let minimumTemperature: Double
    let maximumTemperature: Double
    let step: Double

    init?(status: ThermostatStatus) {
        guard
            let low = status.targetTemperatureLow,
            let high = status.targetTemperatureHigh,
            low.isFinite,
            high.isFinite
        else {
            return nil
        }

        let reportedMinimum = status.minimumTemperature?.isFinite == true ? status.minimumTemperature! : 45
        let reportedMaximum = status.maximumTemperature?.isFinite == true ? status.maximumTemperature! : 95
        guard reportedMaximum - reportedMinimum >= Self.minimumDelta else {
            return nil
        }

        minimumTemperature = reportedMinimum
        maximumTemperature = reportedMaximum
        // Ecobee setpoints are adjusted in whole-degree increments in the app,
        // even if Home Assistant reports a finer-grained target step.
        step = Self.controlStep
        self.low = min(max(low, reportedMinimum), reportedMaximum)
        self.high = min(max(high, reportedMinimum), reportedMaximum)
    }

    var isValid: Bool {
        high - low >= Self.minimumDelta
    }

    var availableMinSetpoints: [Int] {
        wholeDegreeSetpoints(
            minimum: minimumTemperature,
            maximum: maximumTemperature - Self.minimumDelta
        )
    }

    var availableMaxSetpoints: [Int] {
        wholeDegreeSetpoints(
            minimum: minimumTemperature + Self.minimumDelta,
            maximum: maximumTemperature
        )
    }

    mutating func setLow(_ value: Double) {
        low = snapAndClamp(value, minimum: minimumTemperature, maximum: maximumTemperature - Self.minimumDelta)

        if high - low < Self.minimumDelta {
            high = snapAndClamp(low + Self.minimumDelta, minimum: minimumTemperature + Self.minimumDelta, maximum: maximumTemperature)
        }
    }

    mutating func setHigh(_ value: Double) {
        high = snapAndClamp(value, minimum: minimumTemperature + Self.minimumDelta, maximum: maximumTemperature)

        if high - low < Self.minimumDelta {
            low = snapAndClamp(high - Self.minimumDelta, minimum: minimumTemperature, maximum: maximumTemperature - Self.minimumDelta)
        }
    }

    private func snapAndClamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        let clamped = min(max(value, minimum), maximum)
        let snapped = (clamped / step).rounded() * step
        return min(max(snapped, minimum), maximum)
    }

    private func wholeDegreeSetpoints(minimum: Double, maximum: Double) -> [Int] {
        let lowest = Int(minimum.rounded(.up))
        let highest = Int(maximum.rounded(.down))
        guard lowest <= highest else {
            return []
        }

        return Array(lowest...highest)
    }
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
