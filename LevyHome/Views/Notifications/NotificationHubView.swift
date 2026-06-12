import SwiftUI

struct NotificationHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                InfoPanel(
                    title: "Notifications",
                    subtitle: "Delivery status and garage notification preferences",
                    systemImage: "bell"
                ) {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Notification delivery status will appear here without raw token details.")
                            .font(.body)
                            .foregroundStyle(AppColors.mutedText)
                            .fixedSize(horizontal: false, vertical: true)

                        StatusBadgeView(label: "Permission pending", systemImage: "bell.badge", tone: .warning)
                    }
                }

                NotificationPreferencesView()
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Notifications")
    }
}

#Preview {
    NavigationStack {
        NotificationHubView()
    }
}
