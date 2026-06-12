import SwiftUI

struct AppEnvironment {
    let config: AppConfig
    let apiClient: APIClient
    let homeStatusService: HomeStatusServicing
    let notificationPreferencesService: NotificationPreferencesService

    init(
        config: AppConfig,
        apiClient: APIClient? = nil,
        homeStatusService: HomeStatusServicing? = nil,
        notificationPreferencesService: NotificationPreferencesService? = nil
    ) {
        self.config = config
        let resolvedAPIClient = apiClient ?? APIClient(baseURL: config.apiBaseURL)
        self.apiClient = resolvedAPIClient
        self.homeStatusService = homeStatusService ?? HomeStatusService(apiClient: resolvedAPIClient)
        self.notificationPreferencesService = notificationPreferencesService ?? NotificationPreferencesService()
    }

    static func live(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> AppEnvironment {
        let config = AppConfig(
            bundle: bundle,
            processInfo: processInfo
        )

        return AppEnvironment(
            config: config
        )
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
