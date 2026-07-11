import SwiftUI

struct DebugView: View {
    @EnvironmentObject private var shoppingLiveActivityCoordinator: ShoppingLiveActivityCoordinator
    @ObservedObject var pushRegistrationViewModel: PushRegistrationViewModel
    @ObservedObject var notificationPreferencesViewModel: NotificationPreferencesViewModel
    @StateObject private var notificationTestViewModel: NotificationPipelineTestViewModel
    let apnsEnvironment: APNsEnvironment
    let showsDebugControls: Bool

    init(
        pushRegistrationViewModel: PushRegistrationViewModel,
        notificationPreferencesViewModel: NotificationPreferencesViewModel,
        apnsEnvironment: APNsEnvironment,
        showsDebugControls: Bool = true,
        sendNotificationPipelineTest: @escaping () async throws -> TestNotificationPipelineResponse
    ) {
        self.pushRegistrationViewModel = pushRegistrationViewModel
        self.notificationPreferencesViewModel = notificationPreferencesViewModel
        self.apnsEnvironment = apnsEnvironment
        self.showsDebugControls = showsDebugControls
        _notificationTestViewModel = StateObject(
            wrappedValue: NotificationPipelineTestViewModel(sendTest: sendNotificationPipelineTest)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                if showsDebugControls {
                    debugControlSections
                }

                InfoPanel(
                    title: "Logs and Activity",
                    subtitle: "Local diagnostics and the Home Assistant event timeline.",
                    systemImage: "terminal"
                ) {
                    VStack(spacing: 0) {
                        developerLink(
                            title: "Logs",
                            detail: "View local runtime entries collected by the app.",
                            systemImage: "list.bullet.rectangle",
                            accessibilityLabel: "Logs"
                        ) {
                            LogsView()
                        }

                        Divider()
                            .padding(.vertical, AppSpacing.medium)

                        developerLink(
                            title: "Activity",
                            detail: "View recent home activity events.",
                            systemImage: "clock",
                            accessibilityLabel: "Activity"
                        ) {
                            ActivityView()
                        }
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Developer")
        .task {
            if showsDebugControls {
                shoppingLiveActivityCoordinator.refreshState()
                await pushRegistrationViewModel.refreshStatus()
            }
        }
    }

    @ViewBuilder
    private var debugControlSections: some View {
        InfoPanel(
            title: "Shopping Live Activity",
            subtitle: "Stage 1 local Lock Screen and Dynamic Island proof.",
            systemImage: "cart.badge.clock"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                statusRow(
                    title: "Authorization",
                    detail: shoppingLiveActivityAuthorizationDetail,
                    badgeLabel: shoppingLiveActivityCoordinator.activitiesAreEnabled ? "Enabled" : "Disabled",
                    badgeImage: shoppingLiveActivityCoordinator.activitiesAreEnabled
                        ? "checkmark.circle"
                        : "exclamationmark.triangle",
                    badgeTone: shoppingLiveActivityCoordinator.activitiesAreEnabled ? .success : .warning
                )

                statusRow(
                    title: "Sample activity",
                    detail: shoppingLiveActivityStatusDetail,
                    badgeLabel: shoppingLiveActivityCoordinator.hasActiveActivity ? "Active" : "Stopped",
                    badgeImage: shoppingLiveActivityCoordinator.hasActiveActivity ? "cart.fill" : "cart",
                    badgeTone: shoppingLiveActivityCoordinator.hasActiveActivity ? .accent : .neutral
                )

                ErrorBannerView(
                    message: shoppingLiveActivityCoordinator.statusMessage,
                    tone: shoppingLiveActivityMessageTone
                )

                Text("Tap Update repeatedly to cycle through 0, 3, 99, and 999 items left, with estimates from $0.00 through $9,999.99.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(
                    title: "Start Sample Activity",
                    systemImage: "play.fill",
                    isDisabled: shoppingLiveActivityCoordinator.hasActiveActivity
                        || shoppingLiveActivityCoordinator.isRunningOperation
                ) {
                    Task {
                        await shoppingLiveActivityCoordinator.startSampleActivity()
                    }
                }

                PrimaryActionButton(
                    title: "Update Sample Activity",
                    systemImage: "arrow.triangle.2.circlepath",
                    isDisabled: !shoppingLiveActivityCoordinator.hasActiveActivity
                        || shoppingLiveActivityCoordinator.isRunningOperation
                ) {
                    Task {
                        await shoppingLiveActivityCoordinator.updateSampleActivity()
                    }
                }

                PrimaryActionButton(
                    title: "End Sample Activity",
                    systemImage: "stop.fill",
                    isDisabled: !shoppingLiveActivityCoordinator.hasActiveActivity
                        || shoppingLiveActivityCoordinator.isRunningOperation
                ) {
                    Task {
                        await shoppingLiveActivityCoordinator.endSampleActivity()
                    }
                }
            }
        }

        InfoPanel(
            title: "Native Push",
            subtitle: "APNs registration for this device.",
            systemImage: "antenna.radiowaves.left.and.right"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                statusRow(
                    title: "Permission",
                    detail: pushRegistrationViewModel.permissionDetail,
                    badgeLabel: pushRegistrationViewModel.permissionLabel,
                    badgeImage: pushRegistrationViewModel.permissionSystemImage,
                    badgeTone: pushRegistrationViewModel.permissionTone
                )

                statusRow(
                    title: "APNs token",
                    detail: pushRegistrationViewModel.registrationDetail,
                    badgeLabel: pushRegistrationViewModel.registrationLabel,
                    badgeImage: pushRegistrationViewModel.registrationSystemImage,
                    badgeTone: pushRegistrationViewModel.registrationTone
                )

                statusRow(
                    title: "API registration",
                    detail: pushRegistrationViewModel.apiRegistrationDetail,
                    badgeLabel: pushRegistrationViewModel.apiRegistrationLabel,
                    badgeImage: pushRegistrationViewModel.apiRegistrationSystemImage,
                    badgeTone: pushRegistrationViewModel.apiRegistrationTone
                )

                if let token = pushRegistrationViewModel.deviceToken {
                    tokenView(token)
                }

                if let message = pushRegistrationViewModel.developerStatusMessage {
                    ErrorBannerView(message: message, tone: messageTone)
                }

                PrimaryActionButton(
                    title: "Register And Sync Device",
                    systemImage: "bell.badge",
                    isLoading: pushRegistrationViewModel.isRegistering
                ) {
                    Task {
                        await pushRegistrationViewModel.requestRegistration()
                    }
                }
            }
        }

        InfoPanel(
            title: "Notification Pipeline",
            subtitle: "Home Assistant event ingestion through APNs.",
            systemImage: "bell.badge"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                statusRow(
                    title: "Pipeline test",
                    detail: notificationTestViewModel.statusDetail,
                    badgeLabel: notificationTestViewModel.statusLabel,
                    badgeImage: notificationTestViewModel.statusSystemImage,
                    badgeTone: notificationTestViewModel.statusTone
                )

                if let message = notificationTestViewModel.statusMessage {
                    ErrorBannerView(
                        message: message,
                        tone: notificationTestViewModel.messageTone
                    )
                }

                PrimaryActionButton(
                    title: "Test Notification",
                    systemImage: "bell.badge",
                    isLoading: notificationTestViewModel.isSending
                ) {
                    Task {
                        await notificationTestViewModel.sendTestNotification()
                    }
                }
            }
        }

        InfoPanel(
            title: "Preference Sync",
            subtitle: "API adapter for notification preferences.",
            systemImage: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                statusRow(
                    title: "Notification preferences",
                    detail: notificationPreferencesViewModel.syncDetail,
                    badgeLabel: notificationPreferencesViewModel.syncLabel,
                    badgeImage: notificationPreferencesViewModel.syncSystemImage,
                    badgeTone: notificationPreferencesViewModel.syncTone
                )

                if let message = notificationPreferencesViewModel.developerSyncMessage {
                    ErrorBannerView(
                        message: message,
                        tone: notificationPreferencesViewModel.syncTone == .warning ? .warning : .info
                    )
                }

                PrimaryActionButton(
                    title: "Sync Preferences",
                    systemImage: "arrow.triangle.2.circlepath",
                    isLoading: notificationPreferencesViewModel.isSyncing
                ) {
                    Task {
                        await notificationPreferencesViewModel.syncPreferences(
                            deviceToken: pushRegistrationViewModel.deviceToken,
                            environment: apnsEnvironment
                        )
                    }
                }
            }
        }
    }

    private var messageTone: BannerTone {
        switch pushRegistrationViewModel.registrationTone {
        case .success:
            return .success
        case .warning:
            return .warning
        case .critical:
            return .error
        case .neutral, .accent:
            return .info
        }
    }

    private var shoppingLiveActivityAuthorizationDetail: String {
        shoppingLiveActivityCoordinator.activitiesAreEnabled
            ? "iOS currently allows Levy Home to show Live Activities."
            : "Enable Live Activities for Levy Home in iOS Settings to run this proof."
    }

    private var shoppingLiveActivityStatusDetail: String {
        guard let activityID = shoppingLiveActivityCoordinator.activeActivityID else {
            return "No local sample is running. The real Shopping New button remains unchanged."
        }

        return "Local sample ID: \(activityID)"
    }

    private var shoppingLiveActivityMessageTone: BannerTone {
        guard shoppingLiveActivityCoordinator.activitiesAreEnabled else {
            return .warning
        }

        switch shoppingLiveActivityCoordinator.lastResult?.kind {
        case .started, .recovered, .updated, .ended:
            return .success
        case .unavailable:
            return .warning
        case .failed:
            return .error
        case nil:
            return .info
        }
    }

    private func statusRow(
        title: String,
        detail: String,
        badgeLabel: String,
        badgeImage: String,
        badgeTone: StatusBadgeTone
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.medium)

            StatusBadgeView(
                label: badgeLabel,
                systemImage: badgeImage,
                tone: badgeTone
            )
        }
    }

    private func tokenView(_ token: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("Device token")
                .font(.subheadline.weight(.semibold))

            Text(token)
                .font(.footnote.monospaced())
                .foregroundStyle(AppColors.mutedText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
    }

    private func developerLink<Destination: View>(
        title: String,
        detail: String,
        systemImage: String,
        accessibilityLabel: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    NavigationStack {
        DebugView(
            pushRegistrationViewModel: PushRegistrationViewModel(
                service: PreviewNotificationService()
            ),
            notificationPreferencesViewModel: NotificationPreferencesViewModel(
                service: NotificationPreferencesService(
                    userDefaults: UserDefaults(suiteName: "DebugPreview") ?? .standard
                )
            ),
            apnsEnvironment: .sandbox,
            sendNotificationPipelineTest: {
                TestNotificationPipelineResponse.previewSuccess
            }
        )
    }
    .environmentObject(ShoppingLiveActivityCoordinator())
}

@MainActor
private final class NotificationPipelineTestViewModel: ObservableObject {
    @Published private(set) var statusLabel = "Not run"
    @Published private(set) var statusDetail = "No notification pipeline test has run yet."
    @Published private(set) var statusTone: StatusBadgeTone = .neutral
    @Published private(set) var statusSystemImage = "bell"
    @Published private(set) var statusMessage: String?
    @Published private(set) var messageTone: BannerTone = .info
    @Published private(set) var isSending = false

    private let sendTest: () async throws -> TestNotificationPipelineResponse

    init(sendTest: @escaping () async throws -> TestNotificationPipelineResponse) {
        self.sendTest = sendTest
    }

    func sendTestNotification() async {
        guard !isSending else {
            return
        }

        isSending = true
        statusLabel = "Sending"
        statusDetail = "Creating a Home Assistant-style event."
        statusTone = .accent
        statusSystemImage = "arrow.triangle.2.circlepath"
        statusMessage = nil
        defer {
            isSending = false
        }

        do {
            apply(try await sendTest())
        } catch {
            statusLabel = "Failed"
            statusDetail = "The API could not run the notification pipeline test."
            statusTone = .critical
            statusSystemImage = "exclamationmark.triangle"
            statusMessage = "Notification pipeline test failed: \(error.localizedDescription)"
            messageTone = .error
        }
    }

    private func apply(_ response: TestNotificationPipelineResponse) {
        let sentCount = response.sentNotificationCount ?? response.event.push?.sentNotificationCount ?? 0
        let failedCount = response.failedNotificationCount ?? response.event.push?.failedNotificationCount ?? 0
        let skipped = response.skipped ?? response.event.push?.skipped ?? false

        statusMessage = response.message

        if sentCount > 0 {
            statusLabel = "Sent"
            statusDetail = response.message
            statusTone = .success
            statusSystemImage = "checkmark.circle"
            messageTone = .success
            return
        }

        if failedCount > 0 {
            statusLabel = "Failed"
            statusDetail = response.message
            statusTone = .critical
            statusSystemImage = "exclamationmark.triangle"
            messageTone = .error
            return
        }

        if skipped {
            statusLabel = "Skipped"
            statusDetail = response.reason ?? response.message
            statusTone = .warning
            statusSystemImage = "forward"
            messageTone = .warning
            return
        }

        statusLabel = "Created"
        statusDetail = response.message
        statusTone = .warning
        statusSystemImage = "bell.slash"
        messageTone = .warning
    }
}

private struct PreviewNotificationService: NotificationServicing {
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
                    reason: nil,
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
