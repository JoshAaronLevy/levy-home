import SwiftUI

struct NotificationHubView: View {
    var body: some View {
        VStack(spacing: 24) {
            PlaceholderScreen(
                title: "Notifications",
                systemImage: "bell",
                message: "Delivery status and garage notification preferences will appear here."
            )

            NotificationPreferencesView()
        }
        .padding()
        .navigationTitle("Notifications")
    }
}

#Preview {
    NavigationStack {
        NotificationHubView()
    }
}
