import SwiftUI

struct RecentImportantEventData {
    let title: String
    let detail: String
    let timestamp: String
    let tone: StatusBadgeTone
}

struct RecentImportantEventView: View {
    let data: RecentImportantEventData

    var body: some View {
        InfoPanel(
            title: "Recent Important Event",
            subtitle: data.timestamp,
            systemImage: "sparkles"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text(data.title)
                        .font(.headline)

                    Spacer(minLength: AppSpacing.medium)

                    StatusBadgeView(label: "Sample", tone: data.tone)
                }

                Text(data.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    RecentImportantEventView(data: PreviewData.recentImportantEvent)
        .padding()
        .background(AppColors.pageBackground)
}
