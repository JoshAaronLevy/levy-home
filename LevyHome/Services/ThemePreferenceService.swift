import Foundation

protocol ThemePreferenceServicing {
    func loadThemePreference() -> ThemePreference
    func saveThemePreference(_ preference: ThemePreference)
}

final class ThemePreferenceService: ThemePreferenceServicing {
    private let userDefaults: UserDefaults
    private let key = "themePreference"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadThemePreference() -> ThemePreference {
        guard
            let rawValue = userDefaults.string(forKey: key),
            let preference = ThemePreference(rawValue: rawValue)
        else {
            return .system
        }

        return preference
    }

    func saveThemePreference(_ preference: ThemePreference) {
        userDefaults.set(preference.rawValue, forKey: key)
    }
}
