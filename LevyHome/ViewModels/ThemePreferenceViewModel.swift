import SwiftUI

@MainActor
final class ThemePreferenceViewModel: ObservableObject {
    @Published private(set) var preference: ThemePreference

    private let service: ThemePreferenceServicing

    init(service: ThemePreferenceServicing) {
        self.service = service
        preference = service.loadThemePreference()
    }

    var options: [ThemePreference] {
        ThemePreference.allCases
    }

    var selectedTitle: String {
        preference.title
    }

    var preferredColorScheme: ColorScheme? {
        switch preference {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    func select(_ preference: ThemePreference) {
        service.saveThemePreference(preference)
        self.preference = preference
    }
}
