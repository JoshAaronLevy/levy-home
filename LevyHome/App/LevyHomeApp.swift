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
                    await scheduleTomorrowPreviewIfPossible()
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

    @MainActor
    private func scheduleTomorrowPreviewIfPossible() async {
        let calendar = Calendar.current
        guard let firstDeliveryDate = NotificationService.nextTomorrowPreviewDeliveryDate(calendar: calendar) else {
            return
        }

        let previews = (0..<14).compactMap { offset -> (eventCount: Int, deliveryDate: Date)? in
            guard
                let deliveryDate = calendar.date(byAdding: .day, value: offset, to: firstDeliveryDate),
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: deliveryDate),
                let eventCount = FamilyCalendarService.shared.familyEventCount(on: tomorrow)
            else {
                return nil
            }

            return (eventCount: eventCount, deliveryDate: deliveryDate)
        }

        guard !previews.isEmpty else {
            return
        }

        await NotificationService.shared.scheduleTomorrowPreviews(
            previews,
            calendar: calendar
        )
    }
}
