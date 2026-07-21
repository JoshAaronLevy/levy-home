import SwiftUI

struct AppEnvironment {
    let config: AppConfig
    let appLogStore: AppLogStore
    let apiClient: APIClient
    let cameraService: CameraService
    let homeStatusService: HomeStatusServicing
    let homeWeatherService: HomeWeatherServicing
    let quickActionService: QuickActionServicing
    let notificationPreferencesService: NotificationPreferencesService
    let themePreferenceService: ThemePreferenceService
    let notificationService: NotificationServicing

    init(
        config: AppConfig,
        appLogStore: AppLogStore? = nil,
        apiClient: APIClient? = nil,
        cameraService: CameraService? = nil,
        homeStatusService: HomeStatusServicing? = nil,
        homeWeatherService: HomeWeatherServicing? = nil,
        quickActionService: QuickActionServicing? = nil,
        notificationPreferencesService: NotificationPreferencesService? = nil,
        themePreferenceService: ThemePreferenceService? = nil,
        notificationService: NotificationServicing? = nil
    ) {
        self.config = config
        let resolvedLogStore = appLogStore ?? AppLogStore()
        let resolvedAPIClient = apiClient ?? APIClient(baseURL: config.apiBaseURL, appLogStore: resolvedLogStore)
        self.appLogStore = resolvedLogStore
        self.apiClient = resolvedAPIClient
        self.cameraService = cameraService ?? CameraService(
            apiClient: resolvedAPIClient,
            cameraAccessToken: config.cameraAccessToken,
            appLogStore: resolvedLogStore
        )
        self.homeStatusService = homeStatusService ?? HomeStatusService(apiClient: resolvedAPIClient)
        self.homeWeatherService = homeWeatherService ?? HomeWeatherService(appLogStore: resolvedLogStore)
        self.quickActionService = quickActionService ?? QuickActionService(
            apiClient: resolvedAPIClient,
            appLogStore: resolvedLogStore
        )
        self.notificationPreferencesService = notificationPreferencesService ?? NotificationPreferencesService(
            apiClient: resolvedAPIClient
        )
        self.themePreferenceService = themePreferenceService ?? ThemePreferenceService()
        if let notificationService {
            self.notificationService = notificationService
        } else {
            self.notificationService = NotificationService.shared
        }
    }

    static func live(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> AppEnvironment {
        let processEnvironmentValue = processInfo.environment["LEVY_HOME_CAMERA_ACCESS_TOKEN"]
        let bundleInfoValue = bundle.object(forInfoDictionaryKey: "LevyHomeCameraAccessToken") as? String
        let config = AppConfig(
            bundle: bundle,
            processInfo: processInfo
        )
        let environment = AppEnvironment(config: config)
        let diagnostics = CameraAccessConfigurationDiagnostics(
            processEnvironmentValue: processEnvironmentValue,
            bundleInfoValue: bundleInfoValue,
            resolvedToken: config.cameraAccessToken
        )

        environment.appLogStore.record(
            level: diagnostics.resolvedTokenIsAvailable ? .success : .warning,
            category: "Camera",
            title: "Camera configuration resolved",
            detail: diagnostics.logDetail
        )

        return environment
    }
}

struct AppLogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: AppLogLevel
    let category: String
    let title: String
    let detail: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: AppLogLevel,
        category: String,
        title: String,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.title = title
        self.detail = detail
    }
}

final class AppLogStore: ObservableObject, APIClientLogging {
    @Published private(set) var entries: [AppLogEntry]

    private let userDefaults: UserDefaults
    private let storageKey = "appLogEntries"
    private let maxEntryCount = 200

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        entries = Self.loadEntries(from: userDefaults, key: storageKey)
    }

    func record(
        level: AppLogLevel,
        category: String,
        title: String,
        detail: String? = nil
    ) {
        let entry = AppLogEntry(
            level: level,
            category: category,
            title: title,
            detail: detail
        )

        Task { @MainActor in
            self.add(entry)
        }
    }

    @MainActor
    func clear() {
        entries = []
        persist()
    }

    @MainActor
    private func add(_ entry: AppLogEntry) {
        entries.insert(entry, at: 0)

        if entries.count > maxEntryCount {
            entries = Array(entries.prefix(maxEntryCount))
        }

        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }

    private static func loadEntries(from userDefaults: UserDefaults, key: String) -> [AppLogEntry] {
        guard
            let data = userDefaults.data(forKey: key),
            let entries = try? JSONDecoder().decode([AppLogEntry].self, from: data)
        else {
            return []
        }

        return entries
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.live()
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
