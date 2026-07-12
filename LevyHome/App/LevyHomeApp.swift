import SwiftUI

@main
struct LevyHomeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let appEnvironment: AppEnvironment
    @StateObject private var themePreferenceViewModel: ThemePreferenceViewModel
    @StateObject private var pushRegistrationViewModel: PushRegistrationViewModel
    @StateObject private var shoppingLiveActivityCoordinator: ShoppingLiveActivityCoordinator
    @AppStorage private var currentResidentName: String

    init() {
        ResidentPreference.migrateFromStandardDefaults()
        _currentResidentName = AppStorage(
            wrappedValue: ResidentDeviceOwnerDefaults.defaultName,
            ResidentPreference.storageKey,
            store: ResidentPreference.sharedDefaults
        )

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
                .environmentObject(pushRegistrationViewModel)
                .environmentObject(shoppingLiveActivityCoordinator)
                .preferredColorScheme(themePreferenceViewModel.preferredColorScheme)
                .task(id: "\(notificationRegistrationDeviceName ?? ""):\(pushRegistrationViewModel.registeredDeviceID ?? "")") {
                    pushRegistrationViewModel.updateDeviceName(notificationRegistrationDeviceName)
                    await pushRegistrationViewModel.prepareDeliveryIfNeeded()
                    shoppingLiveActivityCoordinator.configureRemotePushRegistration(
                        service: appEnvironment.apiClient,
                        pushDeviceId: pushRegistrationViewModel.registeredDeviceID,
                        resident: notificationRegistrationDeviceName,
                        environment: appEnvironment.config.apiAPNsEnvironment
                    )
                }
        }
    }

    private var notificationRegistrationDeviceName: String? {
        let trimmedName = currentResidentName.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedName.isEmpty ? nil : trimmedName
    }
}
