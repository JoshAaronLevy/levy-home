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
    @AppStorage(ResidentPreference.storageKey) private var currentResidentName = ResidentPreference.defaultName
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

                ResidentPreferenceRowView(currentResidentName: $currentResidentName)

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

private struct ResidentPreferenceRowView: View {
    @Binding var currentResidentName: String

    var body: some View {
        InfoPanel(
            title: "Device Owner",
            subtitle: nil,
            systemImage: "person.crop.circle"
        ) {
            NavigationLink {
                ResidentPreferenceView(currentResidentName: $currentResidentName)
            } label: {
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: selectedResident?.systemImage ?? "person.crop.circle.badge.questionmark")
                        .font(.title3)
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text("This iPhone")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(selectedResident?.rawValue ?? "Choose resident")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.mutedText)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.mutedText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var selectedResident: ResidentIdentity? {
        ResidentIdentity(rawValue: currentResidentName)
    }
}

private struct ResidentPreferenceView: View {
    @Binding var currentResidentName: String

    var body: some View {
        ScrollView {
            InfoPanel(
                title: "Device Owner",
                subtitle: nil,
                systemImage: "person.crop.circle"
            ) {
                VStack(spacing: 0) {
                    ForEach(ResidentIdentity.allCases) { resident in
                        residentButton(resident)

                        if resident.id != ResidentIdentity.allCases.last?.id {
                            Divider()
                                .padding(.vertical, AppSpacing.medium)
                        }
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Device Owner")
    }

    private func residentButton(_ resident: ResidentIdentity) -> some View {
        Button {
            currentResidentName = resident.rawValue
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: resident.systemImage)
                    .font(.title3)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 28)

                Text(resident.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if currentResidentName == resident.rawValue {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(resident.rawValue)
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
