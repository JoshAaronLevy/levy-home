import Combine
import Foundation

@MainActor
final class NotificationPreferencesViewModel: ObservableObject {
    @Published private(set) var preferences: [NotificationPreference]
    @Published private(set) var syncLabel = "Local"
    @Published private(set) var syncDetail = "Saved on this device. Backend enforcement comes later."
    @Published private(set) var syncTone: StatusBadgeTone = .success
    @Published private(set) var syncSystemImage = "checkmark.circle"
    @Published private(set) var developerSyncMessage: String?
    @Published private(set) var isSyncing = false

    private let service: NotificationPreferencesServicing

    init(service: NotificationPreferencesServicing) {
        self.service = service
        preferences = service.loadGaragePreferences()
    }

    func setPreference(_ preference: NotificationPreference, isEnabled: Bool) {
        service.setPreference(preference.category, isEnabled: isEnabled)
        preferences = service.loadGaragePreferences()
        markLocalChanges()
    }

    func syncPreferences(
        deviceToken: String?,
        provider: PushProvider = .apns,
        environment: APNsEnvironment
    ) async {
        guard !isSyncing else {
            return
        }

        guard let deviceToken, !deviceToken.isEmpty else {
            syncLabel = "Not synced"
            syncDetail = "Saved on this device. Sync waits for device registration."
            syncTone = .neutral
            syncSystemImage = "forward"
            developerSyncMessage = "Preference sync skipped: no APNs token is available."
            return
        }

        isSyncing = true
        syncLabel = "Syncing"
        syncDetail = "Saving garage notification preferences to the API."
        syncTone = .accent
        syncSystemImage = "arrow.triangle.2.circlepath"

        defer {
            isSyncing = false
        }

        do {
            _ = try await service.syncGaragePreferences(
                deviceToken: deviceToken,
                provider: provider,
                environment: environment
            )
            syncLabel = "Synced"
            syncDetail = "Saved on this device and synced with the Levy Home API."
            syncTone = .success
            syncSystemImage = "checkmark.circle"
            developerSyncMessage = "Preference sync succeeded."
        } catch {
            syncLabel = "Not synced"
            syncDetail = "Saved on this device. API sync is currently unavailable."
            syncTone = .warning
            syncSystemImage = "exclamationmark.triangle"
            developerSyncMessage = "Preference sync failed: \(error.localizedDescription)"
        }
    }

    private func markLocalChanges() {
        syncLabel = "Local"
        syncDetail = "Saved on this device. Sync has not run for the latest changes."
        syncTone = .success
        syncSystemImage = "checkmark.circle"
    }
}
