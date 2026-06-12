import Foundation

struct GarageStatus: Codable, Equatable {
    enum State: Codable, Equatable, Hashable {
        case open
        case closed
        case opening
        case closing
        case unknown
        case unrecognized(String)

        var rawValue: String {
            switch self {
            case .open:
                return "open"
            case .closed:
                return "closed"
            case .opening:
                return "opening"
            case .closing:
                return "closing"
            case .unknown:
                return "unknown"
            case .unrecognized(let rawValue):
                return rawValue
            }
        }

        init(rawValue: String) {
            switch rawValue {
            case "open":
                self = .open
            case "closed":
                self = .closed
            case "opening":
                self = .opening
            case "closing":
                self = .closing
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
    let displayName: String?
    let lastUpdatedAt: String?
    let isStale: Bool?
}
