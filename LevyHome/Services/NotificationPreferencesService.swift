import Foundation

protocol NotificationPreferencesServicing {
    func loadPreferences() -> [NotificationPreference]
    func setPreference(_ category: NotificationPreferenceCategory, isEnabled: Bool)
    func syncPreferences(
        deviceToken: String,
        provider: PushProvider,
        environment: APNsEnvironment
    ) async throws -> NotificationPreferencesResponse
}

final class NotificationPreferencesService: NotificationPreferencesServicing {
    private let userDefaults: UserDefaults
    private let apiClient: APIClient?
    private let keyPrefix = "notificationPreference"

    init(
        userDefaults: UserDefaults = .standard,
        apiClient: APIClient? = nil
    ) {
        self.userDefaults = userDefaults
        self.apiClient = apiClient
    }

    func loadPreferences() -> [NotificationPreference] {
        Self.defaultPreferences.map { preference in
            NotificationPreference(
                category: preference.category,
                isEnabled: storedValue(for: preference.category) ?? preference.isEnabled,
                title: preference.title,
                detail: preference.detail
            )
        }
    }

    func setPreference(_ category: NotificationPreferenceCategory, isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: key(for: category))
    }

    func syncPreferences(
        deviceToken: String,
        provider: PushProvider = .apns,
        environment: APNsEnvironment
    ) async throws -> NotificationPreferencesResponse {
        guard let apiClient else {
            throw APIError.transport("Notification preference sync is not configured.")
        }

        let request = NotificationPreferencesUpdateRequest(
            preferences: loadPreferences().map {
                NotificationPreferenceUpdate(category: $0.category, isEnabled: $0.isEnabled)
            },
            deviceToken: deviceToken,
            provider: provider,
            environment: environment
        )

        return try await apiClient.updateNotificationPreferences(request)
    }

    private func storedValue(for category: NotificationPreferenceCategory) -> Bool? {
        let key = key(for: category)
        guard userDefaults.object(forKey: key) != nil else {
            return nil
        }

        return userDefaults.bool(forKey: key)
    }

    private func key(for category: NotificationPreferenceCategory) -> String {
        "\(keyPrefix).\(category.rawValue)"
    }

    static let defaultPreferences = [
        NotificationPreference(
            category: .garageOpened,
            isEnabled: true,
            title: "Garage opened",
            detail: "Notify when the garage opens."
        ),
        NotificationPreference(
            category: .garageClosed,
            isEnabled: true,
            title: "Garage closed",
            detail: "Notify when the garage closes."
        ),
        NotificationPreference(
            category: .garageLeftOpen,
            isEnabled: true,
            title: "Garage left open",
            detail: "Notify when the garage has been open for a while."
        ),
        NotificationPreference(
            category: .garageAfterHours,
            isEnabled: true,
            title: "Garage after-hours",
            detail: "Notify when the garage opens late at night."
        ),
        NotificationPreference(
            category: .garageStillOpenAt10PM,
            isEnabled: true,
            title: "Garage still open at 10 PM",
            detail: "Notify at bedtime if the garage is still open."
        ),
        NotificationPreference(
            category: .partnerPresence,
            isEnabled: true,
            title: "Partner presence",
            detail: "Notify when your partner leaves or arrives home."
        ),
        NotificationPreference(
            category: .weatherAlerts,
            isEnabled: true,
            title: "Weather alerts",
            detail: "Notify before rain, storms, snow, or other precipitation is expected."
        ),
        NotificationPreference(
            category: .lightingAutomation,
            isEnabled: true,
            title: "Lighting automations",
            detail: "Notify when selected lighting automations finish."
        )
    ]
}
