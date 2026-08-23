import Foundation

enum NotificationPreferenceCategory: Codable, Equatable, Hashable {
    case garageOpened
    case garageClosed
    case garageLeftOpen
    case garageAfterHours
    case garageStillOpenAt10PM
    case laundry
    case freezer
    case refrigerator
    case partnerPresence
    case doorbell
    case thermostatSetpointHigh
    case weatherAlerts
    case lightingAutomation
    case shoppingList
    case todoList
    case unknown(String)

    var rawValue: String {
        switch self {
        case .garageOpened:
            return "garage_opened"
        case .garageClosed:
            return "garage_closed"
        case .garageLeftOpen:
            return "garage_left_open"
        case .garageAfterHours:
            return "garage_after_hours"
        case .garageStillOpenAt10PM:
            return "garage_still_open_at_10pm"
        case .laundry:
            return "laundry"
        case .freezer:
            return "freezer"
        case .refrigerator:
            return "refrigerator"
        case .partnerPresence:
            return "partner_presence"
        case .doorbell:
            return "doorbell"
        case .thermostatSetpointHigh:
            return "thermostat_setpoint_high"
        case .weatherAlerts:
            return "weather_alerts"
        case .lightingAutomation:
            return "lighting_automation"
        case .shoppingList:
            return "shopping_list"
        case .todoList:
            return "todo_list"
        case .unknown(let rawValue):
            return rawValue
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "garage_opened":
            self = .garageOpened
        case "garage_closed":
            self = .garageClosed
        case "garage_left_open":
            self = .garageLeftOpen
        case "garage_after_hours":
            self = .garageAfterHours
        case "garage_still_open_at_10pm":
            self = .garageStillOpenAt10PM
        case "laundry":
            self = .laundry
        case "freezer":
            self = .freezer
        case "refrigerator":
            self = .refrigerator
        case "partner_presence":
            self = .partnerPresence
        case "doorbell":
            self = .doorbell
        case "thermostat_setpoint_high":
            self = .thermostatSetpointHigh
        case "weather_alerts":
            self = .weatherAlerts
        case "lighting_automation":
            self = .lightingAutomation
        case "shopping_list":
            self = .shoppingList
        case "todo_list":
            self = .todoList
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

struct NotificationPreference: Codable, Equatable, Identifiable {
    var id: NotificationPreferenceCategory { category }

    let category: NotificationPreferenceCategory
    let isEnabled: Bool
    let title: String?
    let detail: String?
}
