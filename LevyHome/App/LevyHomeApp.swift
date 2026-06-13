import SwiftUI

@main
struct LevyHomeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let appEnvironment: AppEnvironment
    @StateObject private var themePreferenceViewModel: ThemePreferenceViewModel

    init() {
        let appEnvironment = AppEnvironment.live()
        self.appEnvironment = appEnvironment
        _themePreferenceViewModel = StateObject(
            wrappedValue: ThemePreferenceViewModel(
                service: appEnvironment.themePreferenceService
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.appEnvironment, appEnvironment)
                .environmentObject(themePreferenceViewModel)
                .preferredColorScheme(themePreferenceViewModel.preferredColorScheme)
        }
    }
}
