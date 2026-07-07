import Foundation

struct LightSummary: Codable, Equatable {
    enum State: Codable, Equatable, Hashable {
        case off
        case on
        case partiallyOn
        case unavailable
        case unknown
        case unrecognized(String)

        var rawValue: String {
            switch self {
            case .off:
                return "off"
            case .on:
                return "on"
            case .partiallyOn:
                return "partially_on"
            case .unavailable:
                return "unavailable"
            case .unknown:
                return "unknown"
            case .unrecognized(let rawValue):
                return rawValue
            }
        }

        init(rawValue: String) {
            switch rawValue {
            case "off":
                self = .off
            case "on":
                self = .on
            case "partially_on", "partiallyOn":
                self = .partiallyOn
            case "unavailable":
                self = .unavailable
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

    let state: State
    let lightsOnCount: Int?
    let totalLightCount: Int?
    let groups: [LightGroupStatus]
}

struct LightGroupStatus: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let state: LightSummary.State
    let lightsOnCount: Int?
    let totalLightCount: Int?
}
