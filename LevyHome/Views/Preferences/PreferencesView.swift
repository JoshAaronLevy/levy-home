import SwiftUI

struct PreferencesView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @EnvironmentObject private var themePreferenceViewModel: ThemePreferenceViewModel

    var body: some View {
        PreferencesContentView(
            viewModel: NotificationPreferencesViewModel(
                service: appEnvironment.notificationPreferencesService
            ),
            pushRegistrationViewModel: PushRegistrationViewModel(
                service: appEnvironment.notificationService,
                deviceRegistrationService: appEnvironment.apiClient,
                apnsEnvironment: appEnvironment.config.apiAPNsEnvironment,
                appVersion: appEnvironment.config.appVersion
            ),
            themePreferenceViewModel: themePreferenceViewModel,
            apnsEnvironment: appEnvironment.config.apiAPNsEnvironment
        )
    }
}

private struct PreferencesContentView: View {
    @StateObject private var viewModel: NotificationPreferencesViewModel
    @StateObject private var pushRegistrationViewModel: PushRegistrationViewModel
    @ObservedObject private var themePreferenceViewModel: ThemePreferenceViewModel
    private let apnsEnvironment: APNsEnvironment

    init(
        viewModel: NotificationPreferencesViewModel,
        pushRegistrationViewModel: PushRegistrationViewModel,
        themePreferenceViewModel: ThemePreferenceViewModel,
        apnsEnvironment: APNsEnvironment = .sandbox
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _pushRegistrationViewModel = StateObject(wrappedValue: pushRegistrationViewModel)
        self.themePreferenceViewModel = themePreferenceViewModel
        self.apnsEnvironment = apnsEnvironment
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                NotificationDeliveryStatusView(
                    viewModel: pushRegistrationViewModel,
                    preferencesViewModel: viewModel
                )

                ThemePreferenceRowView(viewModel: themePreferenceViewModel)

                NotificationPreferencesView(viewModel: viewModel)
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Preferences")
        .toolbar {
            if BuildConfiguration.current.defaultDeveloperToolsEnabled {
                NavigationLink {
                    DebugView(
                        pushRegistrationViewModel: pushRegistrationViewModel,
                        notificationPreferencesViewModel: viewModel,
                        apnsEnvironment: apnsEnvironment
                    )
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .accessibilityLabel("Developer Tools")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PreferencesContentView(
            viewModel: NotificationPreferencesViewModel(
                service: NotificationPreferencesService(
                    userDefaults: UserDefaults(suiteName: "PreferencesPreview") ?? .standard
                )
            ),
            pushRegistrationViewModel: PushRegistrationViewModel(
                service: PreviewPreferencesNotificationService()
            ),
            themePreferenceViewModel: ThemePreferenceViewModel(
                service: ThemePreferenceService(
                    userDefaults: UserDefaults(suiteName: "PreferencesThemePreview") ?? .standard
                )
            ),
            apnsEnvironment: .sandbox
        )
    }
}

private struct PreviewPreferencesNotificationService: NotificationServicing {
    func currentSnapshot() async -> PushRegistrationSnapshot {
        PushRegistrationSnapshot(
            permissionStatus: .authorized,
            availability: .available,
            deviceToken: "0123456789abcdef",
            errorMessage: nil
        )
    }

    func requestAuthorizationAndRegister() async -> PushRegistrationSnapshot {
        await currentSnapshot()
    }
}
