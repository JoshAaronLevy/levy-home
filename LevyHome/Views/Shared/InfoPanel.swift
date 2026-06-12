import SwiftUI

struct InfoPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(title)
                        .font(.headline)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

#Preview {
    InfoPanel(
        title: "Garage",
        subtitle: "Status card placeholder",
        systemImage: "door.garage.closed"
    ) {
        StatusBadgeView(label: "Ready", systemImage: "checkmark.circle", tone: .success)
    }
    .padding()
    .background(AppColors.pageBackground)
}
