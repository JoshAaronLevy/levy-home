import SwiftUI

struct GarageStatusCardData {
    let status: String
    let location: String
    let detail: String
    let systemImage: String
    let tone: StatusBadgeTone
}

struct GarageStatusCard: View {
    let data: GarageStatusCardData

    var body: some View {
        InfoPanel(
            title: "Garage",
            subtitle: data.location,
            systemImage: data.systemImage
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    Text(data.status)
                        .font(.system(.title2, design: .rounded).weight(.semibold))

                    Spacer(minLength: AppSpacing.medium)

                    StatusBadgeView(
                        label: data.status,
                        systemImage: data.systemImage,
                        tone: data.tone
                    )
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
    GarageStatusCard(data: PreviewData.garageStatus)
        .padding()
        .background(AppColors.pageBackground)
}
