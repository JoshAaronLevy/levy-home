import Foundation

enum QuickActionID: Codable, Equatable, Hashable {
    case closeGarage
    case turnOffAllLights
    case turnOffLightGroup
    case unknown(String)

    var rawValue: String {
        switch self {
        case .closeGarage:
            return "close_garage"
        case .turnOffAllLights:
            return "turn_off_all_lights"
        case .turnOffLightGroup:
            return "turn_off_light_group"
        case .unknown(let rawValue):
            return rawValue
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "close_garage":
            self = .closeGarage
        case "turn_off_all_lights":
            self = .turnOffAllLights
        case "turn_off_light_group":
            self = .turnOffLightGroup
        default:
            self = .unknown(rawValue)
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

struct QuickAction: Codable, Equatable, Identifiable {
    let id: QuickActionID
    let title: String
    let subtitle: String?
    let isEnabled: Bool
    let requiresConfirmation: Bool
    let targetName: String?
}

struct QuickActionResult: Codable, Equatable {
    enum Status: Codable, Equatable, Hashable {
        case success
        case failure
        case unknown(String)

        var rawValue: String {
            switch self {
            case .success:
                return "success"
            case .failure:
                return "failure"
            case .unknown(let rawValue):
                return rawValue
            }
        }

        init(rawValue: String) {
            switch rawValue {
            case "success":
                self = .success
            case "failure":
                self = .failure
            default:
                self = .unknown(rawValue)
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

    let actionId: QuickActionID
    let status: Status
    let message: String
    let refreshedHomeOverview: HomeOverview?
}
