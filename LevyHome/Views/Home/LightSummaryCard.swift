import SwiftUI

struct LightGroupSummary: Identifiable {
    let id = UUID()
    let name: String
    let count: String
}

struct LightSummaryCardData {
    let state: String
    let detail: String
    let groups: [LightGroupSummary]
}

struct LightSummaryCard: View {
    let data: LightSummaryCardData

    var body: some View {
        InfoPanel(
            title: "Lights",
            subtitle: data.state,
            systemImage: "lightbulb"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text(data.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 128), spacing: AppSpacing.small)],
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    ForEach(data.groups) { group in
                        HStack {
                            Text(group.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            Spacer(minLength: AppSpacing.small)

                            StatusBadgeView(label: group.count, tone: .warning)
                        }
                        .padding(AppSpacing.small)
                        .background(AppColors.warningSoft)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
                    }
                }
            }
        }
    }
}

#Preview {
    LightSummaryCard(data: PreviewData.lightSummary)
        .padding()
        .background(AppColors.pageBackground)
}
