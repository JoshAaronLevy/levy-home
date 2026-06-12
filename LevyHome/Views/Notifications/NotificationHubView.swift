import SwiftUI

struct NotificationHubView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                InfoPanel(
                    title: "Notification History",
                    subtitle: "Recent delivered notifications will appear here.",
                    systemImage: "bell"
                ) {
                    Text("Notification history will be connected after native push delivery and backend notification records are in place.")
                        .font(.body)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
