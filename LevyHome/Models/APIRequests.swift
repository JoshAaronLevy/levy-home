import Foundation

struct FetchEventsRequest: Encodable, Equatable {
    let limit: Int?
}

enum QuickActionRequest: Encodable, Equatable {
    case closeGarage
    case turnOffAllLights
    case turnOffLightGroup(groupId: String)

    private enum CodingKeys: String, CodingKey {
        case actionId
        case groupId
    }

    var actionId: QuickActionID {
        switch self {
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

struct NotificationPreferenceUpdate: Codable, Equatable {
    let category: NotificationPreferenceCategory
    let isEnabled: Bool
}

struct NotificationPreferencesUpdateRequest: Codable, Equatable {
    let preferences: [NotificationPreferenceUpdate]
}

enum DevicePlatform: String, Codable, Equatable {
    case iOS = "ios"
}

enum PushProvider: String, Codable, Equatable {
    case apns
}

enum APNsEnvironment: String, Codable, Equatable {
    case sandbox
    case production
}

struct RegisterDeviceRequest: Codable, Equatable {
    let token: String
    let platform: DevicePlatform
    let provider: PushProvider
    let environment: APNsEnvironment
    let appVersion: String?
    let deviceName: String?
}

struct TestPushRequest: Codable, Equatable {
    let title: String?
    let body: String?
}
