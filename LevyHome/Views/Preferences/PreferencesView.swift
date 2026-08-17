import SwiftUI

struct PreferencesView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @EnvironmentObject private var themePreferenceViewModel: ThemePreferenceViewModel
    @AppStorage(ResidentPreference.storageKey, store: ResidentPreference.sharedDefaults)
    private var currentResidentName = ResidentDeviceOwnerDefaults.defaultName
    @StateObject private var siriAuthorizationService = SiriAuthorizationService()

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
            siriAuthorizationService: siriAuthorizationService,
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
    @ObservedObject private var siriAuthorizationService: SiriAuthorizationService
    @AppStorage(ResidentPreference.storageKey, store: ResidentPreference.sharedDefaults)
    private var currentResidentName = ResidentDeviceOwnerDefaults.defaultName
    private let apnsEnvironment: APNsEnvironment
    private let isDeveloperToolsEnabled: Bool
    private let sendNotificationPipelineTest: () async throws -> TestNotificationPipelineResponse
    private let sendShoppingLiveActivityDelivery: (ShoppingLiveActivityDebugEvent) async throws -> ShoppingLiveActivityDebugDeliveryResponse

    init(
        viewModel: NotificationPreferencesViewModel,
        pushRegistrationViewModel: PushRegistrationViewModel,
        themePreferenceViewModel: ThemePreferenceViewModel,
        siriAuthorizationService: SiriAuthorizationService,
        apnsEnvironment: APNsEnvironment = .sandbox,
        isDeveloperToolsEnabled: Bool = false,
        sendNotificationPipelineTest: @escaping () async throws -> TestNotificationPipelineResponse,
        sendShoppingLiveActivityDelivery: @escaping (ShoppingLiveActivityDebugEvent) async throws -> ShoppingLiveActivityDebugDeliveryResponse
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _pushRegistrationViewModel = StateObject(wrappedValue: pushRegistrationViewModel)
        self.themePreferenceViewModel = themePreferenceViewModel
        self.siriAuthorizationService = siriAuthorizationService
        self.apnsEnvironment = apnsEnvironment
        self.isDeveloperToolsEnabled = isDeveloperToolsEnabled
        self.sendNotificationPipelineTest = sendNotificationPipelineTest
        self.sendShoppingLiveActivityDelivery = sendShoppingLiveActivityDelivery
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                AppScreenHeader(title: "Settings")

                NotificationDeliveryStatusView(
                    viewModel: pushRegistrationViewModel,
                    preferencesViewModel: viewModel,
                    apnsEnvironment: apnsEnvironment,
                    deviceName: notificationRegistrationDeviceName
                )

                ThemePreferenceRowView(viewModel: themePreferenceViewModel)

                HomeBlueprintPreferenceRowView()

                SiriPreferencesView(authorizationService: siriAuthorizationService)

                ResidentPreferenceRowView(currentResidentName: $currentResidentName)

                NotificationPreferencesView(viewModel: viewModel)

                developerLink

                releaseNotesLink
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
            PreferencesNavigationLinkLabel(
                title: "Developer",
                subtitle: developerSubtitle,
                systemImage: "wrench.and.screwdriver"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Developer")
    }

    private var releaseNotesLink: some View {
        NavigationLink {
            ReleaseNotesView()
        } label: {
            PreferencesNavigationLinkLabel(
                title: "Release Notes",
                subtitle: "See what’s new in Levy Home.",
                systemImage: "text.book.closed"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Release Notes")
    }

    private var developerSubtitle: String {
        isDeveloperToolsEnabled
            ? "Device registration, Live Activities, preference sync, and logs."
            : "Runtime logs and activity diagnostics."
    }

    private var notificationRegistrationDeviceName: String? {
        let trimmedName = currentResidentName.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedName.isEmpty ? nil : trimmedName
    }
}

private struct PreferencesNavigationLinkLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
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
}

private struct ReleaseNotesView: View {
    private let changes = [
        "Add one Shopping or To Do item with Siri while Levy Home is closed.",
        "Use Levy Home add-item shortcuts from Siri, Spotlight, or Shortcuts.",
        "Keep both phones’ shared Shopping and To Do lists current after a Siri change.",
        "Review the latest changes directly from Settings."
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            InfoPanel(
                title: "Version \(latestVersion)",
                subtitle: "Latest release",
                systemImage: "sparkles"
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    Text("What’s new")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    ForEach(changes, id: \.self) { change in
                        HStack(alignment: .top, spacing: AppSpacing.small) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.success)

                            Text(change)
                                .font(.subheadline)
                                .foregroundStyle(AppColors.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Release Notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var latestVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "11.1.1"
    }
}

private struct HomeBlueprintPreferenceRowView: View {
    @AppStorage(HomeBlueprintPreference.storageKey)
    private var defaultBlueprintModeRawValue = HomeBlueprintPreference.defaultMode.rawValue

    private var defaultBlueprintMode: HomeBlueprintMode {
        HomeBlueprintPreference.mode(for: defaultBlueprintModeRawValue)
    }

    var body: some View {
        InfoPanel(
            title: "Home",
            subtitle: nil,
            systemImage: "house"
        ) {
            NavigationLink {
                HomeBlueprintPreferenceView()
            } label: {
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: defaultBlueprintMode.systemImage)
                        .font(.title3)
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text("Default blueprint")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(defaultBlueprintMode.title)
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
}

private struct HomeBlueprintPreferenceView: View {
    @AppStorage(HomeBlueprintPreference.storageKey)
    private var defaultBlueprintModeRawValue = HomeBlueprintPreference.defaultMode.rawValue

    private var defaultBlueprintMode: HomeBlueprintMode {
        HomeBlueprintPreference.mode(for: defaultBlueprintModeRawValue)
    }

    var body: some View {
        ScrollView {
            InfoPanel(
                title: "Default Home blueprint",
                subtitle: "Choose which tab opens when you visit Home on this iPhone.",
                systemImage: "house"
            ) {
                VStack(spacing: 0) {
                    ForEach(HomeBlueprintMode.allCases) { mode in
                        optionButton(mode)

                        if mode != HomeBlueprintMode.allCases.last {
                            Divider()
                                .padding(.vertical, AppSpacing.medium)
                        }
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Home")
    }

    private func optionButton(_ mode: HomeBlueprintMode) -> some View {
        Button {
            defaultBlueprintModeRawValue = mode.rawValue
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: mode.systemImage)
                    .font(.title3)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(mode.defaultPreferenceDetail)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                }

                Spacer()

                if defaultBlueprintMode == mode {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityHint(mode.defaultPreferenceDetail)
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
            siriAuthorizationService: SiriAuthorizationService(),
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
