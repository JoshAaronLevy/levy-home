import Combine
import Foundation

@MainActor
final class NotificationPreferencesViewModel: ObservableObject {
    @Published private(set) var preferences: [NotificationPreference]

    private let service: NotificationPreferencesService

    init(service: NotificationPreferencesService) {
        self.service = service
        preferences = service.loadGaragePreferences()
    }

    func setPreference(_ preference: NotificationPreference, isEnabled: Bool) {
        service.setPreference(preference.category, isEnabled: isEnabled)
        preferences = service.loadGaragePreferences()
    }
}
