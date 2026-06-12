import SwiftUI

struct NotificationPreferencesView: View {
    var body: some View {
        InfoPanel(
            title: "Preferences",
            subtitle: "Garage notification preferences placeholder",
            systemImage: "slider.horizontal.3"
        ) {
            Text("Category toggles will appear here.")
                .font(.body)
                .foregroundStyle(AppColors.mutedText)
        }
    }
}

#Preview {
    NotificationPreferencesView()
}
