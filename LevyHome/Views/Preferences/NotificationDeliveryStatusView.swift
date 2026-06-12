import SwiftUI
import UserNotifications

struct NotificationDeliveryStatusView: View {
    @State private var authorizationStatus: UNAuthorizationStatus?

    var body: some View {
        InfoPanel(
            title: "Delivery Status",
            subtitle: "Current notification readiness for this device.",
            systemImage: "bell.badge"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                deliveryRow(
                    title: "Notifications",
                    detail: permissionDetail,
                    badge: permissionBadge
                )

                deliveryRow(
                    title: "Device registration",
                    detail: "Push registration is not connected yet.",
                    badge: StatusBadgeView(
                        label: "Coming later",
                        systemImage: "iphone",
                        tone: .neutral
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
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    private var permissionBadge: StatusBadgeView {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return StatusBadgeView(label: "Allowed", systemImage: "bell", tone: .success)
        case .denied:
            return StatusBadgeView(label: "Off", systemImage: "bell.slash", tone: .warning)
        case .notDetermined:
            return StatusBadgeView(label: "Not requested", systemImage: "bell.badge", tone: .neutral)
        case nil:
            return StatusBadgeView(label: "Checking", systemImage: "clock", tone: .neutral)
        @unknown default:
            return StatusBadgeView(label: "Unknown", systemImage: "questionmark.circle", tone: .neutral)
        }
    }

    private var permissionDetail: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "iOS allows Levy Home notifications on this device."
        case .denied:
            return "iOS notifications are turned off for Levy Home."
        case .notDetermined:
            return "Levy Home has not asked for notification permission yet."
        case nil:
            return "Checking iOS notification settings."
        @unknown default:
            return "Levy Home could not read the current notification setting."
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
    NotificationDeliveryStatusView()
        .padding()
        .background(AppColors.pageBackground)
}
