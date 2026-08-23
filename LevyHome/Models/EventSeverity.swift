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
    case laundry
    case freezer
    case refrigerator
    case doorbell
    case phone
    case presence
    case lighting
    case thermostat
    case unknown(String)

    var rawValue: String {
        switch self {
        case .garage:
            return "garage"
        case .laundry:
            return "laundry"
        case .freezer:
            return "freezer"
        case .refrigerator:
            return "refrigerator"
        case .doorbell:
            return "doorbell"
        case .phone:
            return "phone"
        case .presence:
            return "presence"
        case .lighting:
            return "lighting"
        case .thermostat:
            return "thermostat"
        case .unknown(let rawValue):
            return rawValue
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "garage":
            self = .garage
        case "laundry":
            self = .laundry
        case "freezer":
            self = .freezer
        case "refrigerator":
            self = .refrigerator
        case "doorbell":
            self = .doorbell
        case "phone":
            self = .phone
        case "presence":
            self = .presence
        case "lighting":
            self = .lighting
        case "thermostat":
            self = .thermostat
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
