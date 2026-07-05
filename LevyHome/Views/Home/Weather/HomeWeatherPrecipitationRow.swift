import SwiftUI

struct HomeWeatherPrecipitationRow: View {
    let summary: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: "cloud.rain.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(HomePalette.blue, Color(red: 0.72, green: 0.82, blue: 0.92))
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("Precipitation")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HomePalette.secondaryInk)

                Text(summary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomePalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
        }
    }
}
