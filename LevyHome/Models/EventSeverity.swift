import Foundation

enum DisplaySeverity: Codable, Equatable, Hashable {
    case info
    case warning
    case critical
    case unknown(String)

    var rawValue: String {
        switch self {
        case .info:
            return "info"
        case .warning:
            return "warning"
        case .critical:
            return "critical"
        case .unknown(let rawValue):
            return rawValue
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "info":
            self = .info
        case "warning":
            self = .warning
        case "critical":
            self = .critical
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

typealias EventSeverity = DisplaySeverity

enum HomeAssistantCategory: Codable, Equatable, Hashable {
    case garage
    case doorbell
    case unknown(String)

    var rawValue: String {
        switch self {
        case .garage:
            return "garage"
        case .doorbell:
            return "doorbell"
        case .unknown(let rawValue):
            return rawValue
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "garage":
            self = .garage
        case "doorbell":
            self = .doorbell
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

enum HomeAssistantPayloadSeverity: Codable, Equatable, Hashable {
    case normal
    case high
    case unknown(String)

    var rawValue: String {
        switch self {
        case .normal:
            return "normal"
        case .high:
            return "high"
        case .unknown(let rawValue):
            return rawValue
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "normal":
            self = .normal
        case "high":
            self = .high
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
