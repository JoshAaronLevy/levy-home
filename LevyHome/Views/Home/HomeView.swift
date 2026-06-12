import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                InfoPanel(
                    title: "Home",
                    subtitle: "Command center placeholder",
                    systemImage: "house"
                ) {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Garage status, light status, recent activity, and quick actions will land here.")
                            .font(.body)
                            .foregroundStyle(AppColors.mutedText)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            StatusBadgeView(label: "Status", systemImage: "sensor", tone: .accent)
                            StatusBadgeView(label: "Actions", systemImage: "bolt", tone: .success)
                        }
                    }
                }

                PrimaryActionButton(
                    title: "Quick Action Placeholder",
                    systemImage: "bolt",
                    isDisabled: true
                ) {}
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Home")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
