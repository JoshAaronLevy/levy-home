import SwiftUI

struct ActivityRibbonRow: View {
    let icon: String
    let tone: StatusBadgeTone
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            ZStack {
                Circle()
                    .fill(tone.backgroundColor)
                    .frame(width: 46, height: 46)

                Image(systemName: icon)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(tone.foregroundColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(HomePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.small)
    }
}
