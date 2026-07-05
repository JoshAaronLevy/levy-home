import SwiftUI

struct InlineStatusView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            ProgressView()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomePalette.ink)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(HomePalette.secondaryInk)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.medium)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
    }
}
