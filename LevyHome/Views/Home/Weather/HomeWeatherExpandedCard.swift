import SwiftUI

struct HomeWeatherExpandedCard: View {
    let data: HomeWeatherExpandedData
    let isLoading: Bool
    let collapseAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.summary.dateText)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HomePalette.ink)
                        .lineLimit(1)

                    Text(data.summary.conditionText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.small)

                if isLoading && data.summary.isPlaceholder {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 34)
                } else {
                    Image(systemName: data.summary.systemImage)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(HomePalette.gold, Color(red: 0.72, green: 0.82, blue: 0.92))
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 34)
                }

                VStack(alignment: .trailing, spacing: 3) {
                    Text(data.summary.currentTemperatureText)
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(HomePalette.ink)
                        .lineLimit(1)

                    Text(data.summary.highLowTemperatureText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                }

                WeatherPanelToggleButton(
                    systemName: "chevron.up",
                    accessibilityLabel: "Collapse weather",
                    action: collapseAction
                )
            }

            HomeWeatherTemperatureChart(data: data.chart)

            Divider()
                .overlay(HomePalette.hairline)

            HomeWeatherPrecipitationRow(summary: data.precipitationSummary)

            Divider()
                .overlay(HomePalette.hairline)

            HomeWeatherTomorrowSection(data: data.tomorrow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
        .shadow(color: HomePalette.shadow.opacity(0.45), radius: 12, y: 6)
    }
}
