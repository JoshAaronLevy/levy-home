import SwiftUI

struct LightGroupSummary: Identifiable {
    let id: String
    let name: String
    let state: LightSummary.State
    let count: String

    init(id: String = UUID().uuidString, name: String, state: LightSummary.State = .unknown, count: String) {
        self.id = id
        self.name = name
        self.state = state
        self.count = count
    }

    var tone: StatusBadgeTone {
        switch state {
        case .off:
            return .neutral
        case .on, .partiallyOn:
            return .warning
        case .unavailable:
            return .critical
        case .unknown, .unrecognized:
            return .neutral
        }
    }
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

                            StatusBadgeView(label: group.count, tone: group.tone)
                        }
                        .padding(AppSpacing.small)
                        .background(group.tone.backgroundColor)
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
