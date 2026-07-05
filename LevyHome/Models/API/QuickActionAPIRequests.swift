enum QuickActionRequest: Encodable, Equatable {
    case openGarage
    case closeGarage
    case turnOffAllLights
    case turnOffLightGroup(groupId: String)

    private enum CodingKeys: String, CodingKey {
        case actionId
        case groupId
    }

    var actionId: QuickActionID {
        switch self {
        case .openGarage:
            return .openGarage
        case .closeGarage:
            return .closeGarage
        case .turnOffAllLights:
            return .turnOffAllLights
        case .turnOffLightGroup:
            return .turnOffLightGroup
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionId, forKey: .actionId)

        if case .turnOffLightGroup(let groupId) = self {
            try container.encode(groupId, forKey: .groupId)
        }
    }
}
