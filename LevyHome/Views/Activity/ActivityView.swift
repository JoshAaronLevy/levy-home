import SwiftUI

struct ActivityView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                InfoPanel(
                    title: "Activity",
                    subtitle: "Event history placeholder",
                    systemImage: "clock"
                ) {
                    Text("Recent home events will appear here.")
                        .font(.body)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ErrorBannerView(
                    message: "Live event loading is not connected yet.",
                    tone: .info
                )
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Activity")
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
}
