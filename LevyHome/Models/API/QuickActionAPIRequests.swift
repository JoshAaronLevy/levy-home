enum QuickActionRequest: Encodable, Equatable {
    case openGarage
    case closeGarage
    case turnOffAllLights
    case turnOnLightGroup(groupId: String)
    case turnOffLightGroup(groupId: String)
    case setThermostatTemperature(low: Double, high: Double)

    private enum CodingKeys: String, CodingKey {
        case actionId
        case groupId
        case targetTemperatureLow
        case targetTemperatureHigh
    }

    var actionId: QuickActionID {
        switch self {
        case .openGarage:
            return .openGarage
        case .closeGarage:
            return .closeGarage
        case .turnOffAllLights:
            return .turnOffAllLights
        case .turnOnLightGroup:
            return .turnOnLightGroup
        case .turnOffLightGroup:
            return .turnOffLightGroup
        case .setThermostatTemperature:
            return .setThermostatTemperature
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionId, forKey: .actionId)

        switch self {
        case .turnOnLightGroup(let groupId), .turnOffLightGroup(let groupId):
            try container.encode(groupId, forKey: .groupId)
        case .setThermostatTemperature(let low, let high):
            try container.encode(low, forKey: .targetTemperatureLow)
            try container.encode(high, forKey: .targetTemperatureHigh)
        case .openGarage, .closeGarage, .turnOffAllLights:
            break
        }
    }
}
