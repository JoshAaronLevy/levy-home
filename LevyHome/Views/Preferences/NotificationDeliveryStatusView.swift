import SwiftUI

struct NotificationDeliveryStatusView: View {
    @ObservedObject var viewModel: PushRegistrationViewModel
    @ObservedObject var preferencesViewModel: NotificationPreferencesViewModel

    var body: some View {
        InfoPanel(
            title: "Delivery Status",
            subtitle: "Current notification readiness for this device.",
            systemImage: "bell.badge"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                deliveryRow(
                    title: "Notifications",
                    detail: viewModel.permissionDetail,
                    badge: StatusBadgeView(
                        label: viewModel.permissionLabel,
                        systemImage: viewModel.permissionSystemImage,
                        tone: viewModel.permissionTone
                    )
                )

                deliveryRow(
                    title: "APNs token",
                    detail: viewModel.registrationDetail,
                    badge: StatusBadgeView(
                        label: viewModel.registrationLabel,
                        systemImage: viewModel.registrationSystemImage,
                        tone: viewModel.registrationTone
                    )
                )

                deliveryRow(
                    title: "API sync",
                    detail: viewModel.apiRegistrationDetail,
                    badge: StatusBadgeView(
                        label: viewModel.apiRegistrationLabel,
                        systemImage: viewModel.apiRegistrationSystemImage,
                        tone: productSafeAPITone
                    )
                )

                deliveryRow(
                    title: "Preferences",
                    detail: preferencesViewModel.syncDetail,
                    badge: StatusBadgeView(
                        label: preferencesViewModel.syncLabel,
                        systemImage: preferencesViewModel.syncSystemImage,
                        tone: preferencesViewModel.syncTone
                    )
                )
            }
        }
        .task {
            await viewModel.refreshStatus()
        }
    }

    private var productSafeAPITone: StatusBadgeTone {
        viewModel.apiRegistrationTone == .critical ? .warning : viewModel.apiRegistrationTone
    }

    private func deliveryRow<Badge: View>(
        title: String,
        detail: String,
        badge: Badge
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

            badge
        }
    }
}

#Preview {
    NotificationDeliveryStatusView(
        viewModel: PushRegistrationViewModel(service: PreviewDeliveryNotificationService()),
        preferencesViewModel: NotificationPreferencesViewModel(
            service: NotificationPreferencesService(
                userDefaults: UserDefaults(suiteName: "DeliveryStatusPreview") ?? .standard
            )
        )
    )
        .padding()
        .background(AppColors.pageBackground)
}

private struct PreviewDeliveryNotificationService: NotificationServicing {
    func currentSnapshot() async -> PushRegistrationSnapshot {
        PushRegistrationSnapshot(
            permissionStatus: .notDetermined,
            availability: .simulatorUnavailable,
            deviceToken: nil,
            errorMessage: nil
        )
    }

    func requestAuthorizationAndRegister() async -> PushRegistrationSnapshot {
        await currentSnapshot()
    }
}
