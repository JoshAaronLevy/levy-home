import SwiftUI

@main
struct LevyHomeApp: App {
    private let appEnvironment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.appEnvironment, appEnvironment)
        }
    }
}
