import SwiftUI

struct AppEnvironment {
    let config: AppConfig
    let apiClient: APIClient

    init(config: AppConfig, apiClient: APIClient? = nil) {
        self.config = config
        self.apiClient = apiClient ?? APIClient(baseURL: config.apiBaseURL)
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
