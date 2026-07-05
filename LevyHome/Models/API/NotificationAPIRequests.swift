struct NotificationPreferenceUpdate: Codable, Equatable {
    let category: NotificationPreferenceCategory
    let isEnabled: Bool
}

struct NotificationPreferencesUpdateRequest: Codable, Equatable {
    let preferences: [NotificationPreferenceUpdate]
    let deviceToken: String?
    let provider: PushProvider?
    let environment: APNsEnvironment?

    init(
        preferences: [NotificationPreferenceUpdate],
        deviceToken: String? = nil,
        provider: PushProvider? = nil,
        environment: APNsEnvironment? = nil
    ) {
        self.preferences = preferences
        self.deviceToken = deviceToken
        self.provider = provider
        self.environment = environment
    }
}
