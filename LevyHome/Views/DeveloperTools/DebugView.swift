import SwiftUI

struct DebugView: View {
    @ObservedObject var pushRegistrationViewModel: PushRegistrationViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
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

                        if let token = pushRegistrationViewModel.deviceToken {
                            tokenView(token)
                        }

                        if let message = pushRegistrationViewModel.developerStatusMessage {
                            ErrorBannerView(message: message, tone: messageTone)
                        }

                        PrimaryActionButton(
                            title: "Register For Push",
                            systemImage: "bell.badge",
                            isLoading: pushRegistrationViewModel.isRegistering
                        ) {
                            Task {
                                await pushRegistrationViewModel.requestRegistration()
                            }
                        }
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Developer Tools")
        .task {
            await pushRegistrationViewModel.refreshStatus()
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
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        DebugView(
            pushRegistrationViewModel: PushRegistrationViewModel(
                service: PreviewNotificationService()
            )
        )
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
