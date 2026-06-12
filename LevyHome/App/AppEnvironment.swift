import SwiftUI

struct AppEnvironment {
    let config: AppConfig

    static func live(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> AppEnvironment {
        AppEnvironment(
            config: AppConfig(
                bundle: bundle,
                processInfo: processInfo
            )
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
