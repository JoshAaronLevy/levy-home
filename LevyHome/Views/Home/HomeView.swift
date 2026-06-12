import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                HStack {
                    Spacer(minLength: AppSpacing.medium)

                    StatusBadgeView(label: "Sample data", systemImage: "eye", tone: .neutral)
                }

                GarageStatusCard(data: PreviewData.garageStatus)
                LightSummaryCard(data: PreviewData.lightSummary)
                RecentImportantEventView(data: PreviewData.recentImportantEvent)
                QuickActionsView(actions: PreviewData.quickActions)
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
