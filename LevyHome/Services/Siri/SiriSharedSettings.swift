import Foundation

enum ResidentIdentity: String, CaseIterable, Identifiable {
    case josh = "Josh"
    case mallory = "Mallory"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .josh:
            return "person.crop.circle"
        case .mallory:
            return "person.crop.circle.fill"
        }
    }
}

enum ResidentPreference {
    static let storageKey = "currentResidentName"
    static let migrationKey = "currentResidentName.migratedToAppGroup.v1"
    static let appGroupIdentifier = "group.com.levyhome.app"
    static let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard

    static func migrateFromStandardDefaults(
        standardDefaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults = ResidentPreference.sharedDefaults
    ) {
        guard !sharedDefaults.bool(forKey: migrationKey) else {
            return
        }

        defer {
            sharedDefaults.set(true, forKey: migrationKey)
        }

        guard
            sharedDefaults.object(forKey: storageKey) == nil,
            let legacyValue = standardDefaults.object(forKey: storageKey) as? String
        else {
            return
        }

        sharedDefaults.set(legacyValue, forKey: storageKey)
    }
}

struct SiriSharedSettings {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = ResidentPreference.sharedDefaults) {
        self.userDefaults = userDefaults
    }

    var residentName: String? {
        guard let value = userDefaults.string(forKey: ResidentPreference.storageKey) else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
