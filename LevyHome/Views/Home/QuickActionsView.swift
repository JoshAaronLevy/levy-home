import SwiftUI

struct QuickActionDisplayData: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
}

struct QuickActionsView: View {
    let actions: [QuickActionDisplayData]

    var body: some View {
        InfoPanel(
            title: "Quick Actions",
            subtitle: "Disabled until live action support is connected",
            systemImage: "bolt"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: AppSpacing.small)],
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                ForEach(actions) { action in
                    HStack(spacing: AppSpacing.medium) {
                        Image(systemName: action.systemImage)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.gray)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))

                        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(AppColors.mutedText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(AppSpacing.small)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(action.title), unavailable")
                }
            }
        }
    }
}

#Preview {
    QuickActionsView(actions: PreviewData.quickActions)
        .padding()
        .background(AppColors.pageBackground)
}
