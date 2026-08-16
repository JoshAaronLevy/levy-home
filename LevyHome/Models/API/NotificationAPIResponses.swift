struct NotificationPreferencesResponse: Codable, Equatable {
    let ok: Bool
    let preferences: [NotificationPreference]
    let syncedAt: String?
}

struct RegisteredDevice: Codable, Equatable, Identifiable {
    let id: String?
    let platform: DevicePlatform?
    let provider: PushProvider?
    let environment: APNsEnvironment?
    let registeredAt: String?
    let lastSeenAt: String?
}

struct RegisterDeviceResponse: Codable, Equatable {
    let ok: Bool
    let registeredDeviceCount: Int?
    let device: RegisteredDevice?
}

struct TestPushResponse: Codable, Equatable {
    let ok: Bool
    let message: String
    let registeredDeviceCount: Int
    let sentNotificationCount: Int?
    let sentTicketCount: Int?
    let invalidTokenCount: Int?
    let provider: PushProvider?
}

struct TestNotificationPipelineResponse: Codable, Equatable {
    let ok: Bool
    let message: String
    let provider: PushProvider?
    let event: LevyHomeEvent
    let dedupeKey: String?
    let storedEventCount: Int?
    let sentNotificationCount: Int?
    let failedNotificationCount: Int?
    let invalidTokenCount: Int?
    let skipped: Bool?
    let reason: String?
}
