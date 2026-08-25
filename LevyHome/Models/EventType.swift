import Foundation

enum EventType: Codable, Equatable, Hashable {
    case garageOpened
    case garageClosed
    case garageLeftOpen10Min
    case garageOpenedAfterHours
    case garageStillOpenAt10PM
    case dryerCycleFinished
    case washerCycleFinished
    case washerTransferReminder
    case freezerDoorLeftOpen5Min
    case refrigeratorDoorLeftOpen5Min
    case partnerLeftHome
    case partnerArrivedHome
    case studyLightsOn
    case doorbellPressed
    case doorbellPersonDetected
    case doorbellMotionDetected
    case thermostatSetpointHigh
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
        case .dryerCycleFinished:
            return "dryer_cycle_finished"
        case .washerCycleFinished:
            return "washer_cycle_finished"
        case .washerTransferReminder:
            return "washer_transfer_reminder"
        case .freezerDoorLeftOpen5Min:
            return "freezer_door_left_open_5_min"
        case .refrigeratorDoorLeftOpen5Min:
            return "refrigerator_door_left_open_5_min"
        case .partnerLeftHome:
            return "partner_left_home"
        case .partnerArrivedHome:
            return "partner_arrived_home"
        case .studyLightsOn:
            return "study_lights_on"
        case .doorbellPressed:
            return "doorbell_pressed"
        case .doorbellPersonDetected:
            return "doorbell_person_detected"
        case .doorbellMotionDetected:
            return "doorbell_motion_detected"
        case .thermostatSetpointHigh:
            return "thermostat_setpoint_high"
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
        case "dryer_cycle_finished":
            self = .dryerCycleFinished
        case "washer_cycle_finished":
            self = .washerCycleFinished
        case "washer_transfer_reminder":
            self = .washerTransferReminder
        case "freezer_door_left_open_5_min":
            self = .freezerDoorLeftOpen5Min
        case "refrigerator_door_left_open_5_min":
            self = .refrigeratorDoorLeftOpen5Min
        case "partner_left_home":
            self = .partnerLeftHome
        case "partner_arrived_home":
            self = .partnerArrivedHome
        case "study_lights_on":
            self = .studyLightsOn
        case "doorbell_pressed":
            self = .doorbellPressed
        case "doorbell_person_detected":
            self = .doorbellPersonDetected
        case "doorbell_motion_detected":
            self = .doorbellMotionDetected
        case "thermostat_setpoint_high":
            self = .thermostatSetpointHigh
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
