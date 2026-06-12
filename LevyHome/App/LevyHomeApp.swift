import SwiftUI

@main
struct LevyHomeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let appEnvironment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.appEnvironment, appEnvironment)
        }
    }
}
