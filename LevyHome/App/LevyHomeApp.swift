import SwiftUI

@main
struct LevyHomeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let appEnvironment: AppEnvironment
    @StateObject private var themePreferenceViewModel: ThemePreferenceViewModel
    @StateObject private var pushRegistrationViewModel: PushRegistrationViewModel
    @StateObject private var shoppingLiveActivityCoordinator: ShoppingLiveActivityCoordinator
    @AppStorage(ResidentPreference.storageKey) private var currentResidentName = ResidentPreference.defaultName

    init() {
        let appEnvironment = AppEnvironment.live()
        self.appEnvironment = appEnvironment
        _themePreferenceViewModel = StateObject(
            wrappedValue: ThemePreferenceViewModel(
                service: appEnvironment.themePreferenceService
            )
        )
        _pushRegistrationViewModel = StateObject(
            wrappedValue: PushRegistrationViewModel(
                service: appEnvironment.notificationService,
                deviceRegistrationService: appEnvironment.apiClient,
                apnsEnvironment: appEnvironment.config.apiAPNsEnvironment,
                appVersion: appEnvironment.config.appVersion
            )
        )
        _shoppingLiveActivityCoordinator = StateObject(
            wrappedValue: ShoppingLiveActivityCoordinator()
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.appEnvironment, appEnvironment)
                .environmentObject(themePreferenceViewModel)
                .environmentObject(shoppingLiveActivityCoordinator)
                .preferredColorScheme(themePreferenceViewModel.preferredColorScheme)
                .task(id: notificationRegistrationDeviceName ?? "") {
                    pushRegistrationViewModel.updateDeviceName(notificationRegistrationDeviceName)
                    await pushRegistrationViewModel.prepareDeliveryIfNeeded()
                }
        }
    }

    private var notificationRegistrationDeviceName: String? {
        let trimmedName = currentResidentName.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedName.isEmpty ? nil : trimmedName
    }
}
