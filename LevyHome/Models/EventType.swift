import Foundation

enum EventType: Codable, Equatable, Hashable {
    case garageOpened
    case garageClosed
    case garageLeftOpen10Min
    case garageOpenedAfterHours
    case garageStillOpenAt10PM
    case doorbellPressed
    case doorbellPersonDetected
    case doorbellMotionDetected
    case phoneStateChanged
    case unknown(String)

    var rawValue: String {
        switch self {
        case .garageOpened:
            return "garage_opened"
        case .garageClosed:
            return "garage_closed"
        case .garageLeftOpen10Min:
            return "garage_left_open_10_min"
        case .garageOpenedAfterHours:
            return "garage_opened_after_hours"
        case .garageStillOpenAt10PM:
            return "garage_still_open_at_10pm"
        case .doorbellPressed:
            return "doorbell_pressed"
        case .doorbellPersonDetected:
            return "doorbell_person_detected"
        case .doorbellMotionDetected:
            return "doorbell_motion_detected"
        case .phoneStateChanged:
            return "phone_state_changed"
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
        case "garage_left_open_10_min":
            self = .garageLeftOpen10Min
        case "garage_opened_after_hours":
            self = .garageOpenedAfterHours
        case "garage_still_open_at_10pm":
            self = .garageStillOpenAt10PM
        case "doorbell_pressed":
            self = .doorbellPressed
        case "doorbell_person_detected":
            self = .doorbellPersonDetected
        case "doorbell_motion_detected":
            self = .doorbellMotionDetected
        case "phone_state_changed":
            self = .phoneStateChanged
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
