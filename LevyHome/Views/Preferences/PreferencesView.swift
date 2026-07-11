import SwiftUI

struct PreferencesView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @EnvironmentObject private var themePreferenceViewModel: ThemePreferenceViewModel
    @AppStorage(ResidentPreference.storageKey) private var currentResidentName = ResidentPreference.defaultName

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
            apnsEnvironment: appEnvironment.config.apiAPNsEnvironment,
            isDeveloperToolsEnabled: appEnvironment.config.isDeveloperToolsEnabled,
            sendNotificationPipelineTest: {
                try await appEnvironment.apiClient.sendNotificationPipelineTest()
            },
            sendShoppingLiveActivityDelivery: { event in
                try await appEnvironment.apiClient.sendShoppingLiveActivityDebugDelivery(
                    event: event,
                    excludeResident: currentResidentName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        )
    }
}

private struct PreferencesContentView: View {
    @StateObject private var viewModel: NotificationPreferencesViewModel
    @StateObject private var pushRegistrationViewModel: PushRegistrationViewModel
    @ObservedObject private var themePreferenceViewModel: ThemePreferenceViewModel
    @AppStorage(ResidentPreference.storageKey) private var currentResidentName = ResidentPreference.defaultName
    private let apnsEnvironment: APNsEnvironment
    private let isDeveloperToolsEnabled: Bool
    private let sendNotificationPipelineTest: () async throws -> TestNotificationPipelineResponse
    private let sendShoppingLiveActivityDelivery: (ShoppingLiveActivityDebugEvent) async throws -> ShoppingLiveActivityDebugDeliveryResponse

    init(
        viewModel: NotificationPreferencesViewModel,
        pushRegistrationViewModel: PushRegistrationViewModel,
        themePreferenceViewModel: ThemePreferenceViewModel,
        apnsEnvironment: APNsEnvironment = .sandbox,
        isDeveloperToolsEnabled: Bool = false,
        sendNotificationPipelineTest: @escaping () async throws -> TestNotificationPipelineResponse,
        sendShoppingLiveActivityDelivery: @escaping (ShoppingLiveActivityDebugEvent) async throws -> ShoppingLiveActivityDebugDeliveryResponse
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _pushRegistrationViewModel = StateObject(wrappedValue: pushRegistrationViewModel)
        self.themePreferenceViewModel = themePreferenceViewModel
        self.apnsEnvironment = apnsEnvironment
        self.isDeveloperToolsEnabled = isDeveloperToolsEnabled
        self.sendNotificationPipelineTest = sendNotificationPipelineTest
        self.sendShoppingLiveActivityDelivery = sendShoppingLiveActivityDelivery
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                AppScreenHeader(title: "Preferences")

                NotificationDeliveryStatusView(
                    viewModel: pushRegistrationViewModel,
                    preferencesViewModel: viewModel,
                    apnsEnvironment: apnsEnvironment,
                    deviceName: notificationRegistrationDeviceName
                )

                ThemePreferenceRowView(viewModel: themePreferenceViewModel)

                ResidentPreferenceRowView(currentResidentName: $currentResidentName)

                NotificationPreferencesView(viewModel: viewModel)

                developerLink
            }
            .padding(.horizontal, AppSpacing.screen)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, AppSpacing.xLarge * 3)
        }
        .appScreenChrome()
    }

    private var developerLink: some View {
        NavigationLink {
            DebugView(
                pushRegistrationViewModel: pushRegistrationViewModel,
                notificationPreferencesViewModel: viewModel,
                apnsEnvironment: apnsEnvironment,
                showsDebugControls: isDeveloperToolsEnabled,
                sendNotificationPipelineTest: sendNotificationPipelineTest,
                sendShoppingLiveActivityDelivery: sendShoppingLiveActivityDelivery
            )
        } label: {
            DeveloperPreferenceLinkLabel(showsDebugControls: isDeveloperToolsEnabled)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Developer")
    }

    private var notificationRegistrationDeviceName: String? {
        let trimmedName = currentResidentName.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedName.isEmpty ? nil : trimmedName
    }
}

private struct DeveloperPreferenceLinkLabel: View {
    let showsDebugControls: Bool

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Developer")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    private var subtitle: String {
        showsDebugControls
            ? "Device registration, Live Activities, preference sync, and logs."
            : "Runtime logs and activity diagnostics."
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
            apnsEnvironment: .sandbox,
            isDeveloperToolsEnabled: true,
            sendNotificationPipelineTest: {
                TestNotificationPipelineResponse.previewSuccess
            },
            sendShoppingLiveActivityDelivery: { _ in
                throw URLError(.unsupportedURL)
            }
        )
    }
    .environmentObject(ShoppingLiveActivityCoordinator())
}

private extension TestNotificationPipelineResponse {
    static var previewSuccess: TestNotificationPipelineResponse {
        TestNotificationPipelineResponse(
            ok: true,
            message: "Created a Home Assistant-style test event and sent 1 APNs notification(s).",
            provider: .apns,
            event: LevyHomeEvent(
                id: UUID().uuidString,
                type: .garageStillOpenAt10PM,
                entityId: "debug.notification_pipeline_test",
                category: .garage,
                severity: .high,
                source: "home_assistant_debug_pipeline_test",
                occurredAt: "2026-07-01T12:00:00.000Z",
                title: "Levy Home notification test",
                message: "This push came through the Levy Home event pipeline.",
                receivedAt: "2026-07-01T12:00:00.000Z",
                display: EventDisplayMetadata(
                    title: "Garage still open",
                    body: "The garage is still open at 10 PM.",
                    severity: .critical
                ),
                push: EventPushStatus(
                    attempted: true,
                    skipped: false,
                    ticketCount: 1,
                    sentNotificationCount: 1,
                    failedNotificationCount: 0,
                    invalidTokenCount: 0
                )
            ),
            dedupeKey: "garage_still_open_at_10pm:debug.notification_pipeline_test",
            storedEventCount: 1,
            sentNotificationCount: 1,
            failedNotificationCount: 0,
            invalidTokenCount: 0,
            skipped: false,
            reason: nil
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
