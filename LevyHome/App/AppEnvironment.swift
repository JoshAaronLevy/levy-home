import SwiftUI

struct AppEnvironment {
    let config: AppConfig
    let apiClient: APIClient
    let homeStatusService: HomeStatusServicing
    let quickActionService: QuickActionServicing
    let notificationPreferencesService: NotificationPreferencesService
    let notificationService: NotificationServicing

    init(
        config: AppConfig,
        apiClient: APIClient? = nil,
        homeStatusService: HomeStatusServicing? = nil,
        quickActionService: QuickActionServicing? = nil,
        notificationPreferencesService: NotificationPreferencesService? = nil,
        notificationService: NotificationServicing? = nil
    ) {
        self.config = config
        let resolvedAPIClient = apiClient ?? APIClient(baseURL: config.apiBaseURL)
        self.apiClient = resolvedAPIClient
        self.homeStatusService = homeStatusService ?? HomeStatusService(apiClient: resolvedAPIClient)
        self.quickActionService = quickActionService ?? QuickActionService(apiClient: resolvedAPIClient)
        self.notificationPreferencesService = notificationPreferencesService ?? NotificationPreferencesService()
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
