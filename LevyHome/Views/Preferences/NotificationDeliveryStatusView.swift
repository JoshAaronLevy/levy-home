import SwiftUI

struct NotificationDeliveryStatusView: View {
    @ObservedObject var viewModel: PushRegistrationViewModel

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
                    title: "Device registration",
                    detail: viewModel.registrationDetail,
                    badge: StatusBadgeView(
                        label: viewModel.registrationLabel,
                        systemImage: viewModel.registrationSystemImage,
                        tone: viewModel.registrationTone
                    )
                )

                deliveryRow(
                    title: "Preferences",
                    detail: "Saved on this device. Backend enforcement comes later.",
                    badge: StatusBadgeView(
                        label: "Local",
                        systemImage: "checkmark.circle",
                        tone: .success
                    )
                )
            }
        }
        .task {
            await viewModel.refreshStatus()
        }
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
        viewModel: PushRegistrationViewModel(service: PreviewDeliveryNotificationService())
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
