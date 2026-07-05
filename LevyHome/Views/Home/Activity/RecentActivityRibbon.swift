import SwiftUI

struct RecentActivityRibbon: View {
    let recentEventData: RecentImportantEventData
    let garageData: GarageStatusCardData

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundStyle(HomePalette.ink)

                Spacer()

                Button("See all") {}
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomePalette.blue)
                    .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ActivityRibbonRow(
                    icon: recentIcon,
                    tone: recentEventData.tone,
                    title: recentEventData.title,
                    detail: recentEventData.timestamp
                )

                ActivityRibbonRow(
                    icon: garageData.systemImage,
                    tone: garageData.tone,
                    title: "Garage \(garageData.status.lowercased())",
                    detail: garageData.location
                )
            }
        }
        .padding(AppSpacing.large)
        .background(HomePalette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
    }

    private var recentIcon: String {
        switch recentEventData.tone {
        case .success:
            return "person.fill"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        case .accent:
            return "sparkles"
        case .neutral:
            return "clock"
        }
    }
}
