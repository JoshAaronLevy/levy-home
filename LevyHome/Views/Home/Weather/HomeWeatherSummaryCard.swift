import SwiftUI

struct HomeWeatherSummaryCard: View {
    let data: HomeWeatherSummaryData
    let isLoading: Bool
    let expandAction: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(data.dateText)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(HomePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let attributionURL = data.attributionURL {
                    Link("Weather", destination: attributionURL)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                } else {
                    Text("Weather")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppSpacing.small)

            if isLoading && data.isPlaceholder {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34)
            } else {
                Image(systemName: data.systemImage)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(HomePalette.gold, Color(red: 0.72, green: 0.82, blue: 0.92))
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 34)
            }

            Text(data.currentTemperatureText)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(HomePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Text(data.highLowTemperatureText)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(HomePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            if data.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomePalette.gold)
                    .accessibilityHidden(true)
            }

            WeatherPanelToggleButton(
                systemName: "chevron.down",
                accessibilityLabel: "Expand weather",
                action: expandAction
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.large)
        .frame(height: 58)
        .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
        .shadow(color: HomePalette.shadow.opacity(0.45), radius: 10, y: 5)
    }
}

private struct HomeWeatherSummaryCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: AppSpacing.large) {
            HomeWeatherSummaryCard(
                data: HomeWeatherSummaryData(
                    dateText: "Wed. Jul 1",
                    attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
                    systemImage: "cloud.sun.fill",
                    currentTemperatureText: "74°",
                    highLowTemperatureText: "82°/58°",
                    conditionText: "Partly Cloudy",
                    isPlaceholder: false,
                    isStale: false
                ),
                isLoading: false,
                expandAction: {}
            )

            HomeWeatherExpandedCard(
                data: HomeWeatherExpandedData(
                    summary: HomeWeatherSummaryData(
                        dateText: "Wed. Jul 1",
                        attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html"),
                        systemImage: "cloud.sun.fill",
                        currentTemperatureText: "74°",
                        highLowTemperatureText: "82°/58°",
                        conditionText: "Partly Cloudy",
                        isPlaceholder: false,
                        isStale: false
                    ),
                    chart: HomeWeatherChartData(
                        points: [
                            HomeWeatherChartPoint(id: 1, position: 0.12, temperature: 66),
                            HomeWeatherChartPoint(id: 2, position: 0.28, temperature: 73),
                            HomeWeatherChartPoint(id: 3, position: 0.42, temperature: 80),
                            HomeWeatherChartPoint(id: 4, position: 0.62, temperature: 84),
                            HomeWeatherChartPoint(id: 5, position: 0.82, temperature: 76)
                        ],
                        markers: [
                            HomeWeatherChartMarker(
                                id: "preview-rain-start",
                                position: 0.28,
                                systemImage: "cloud.drizzle.fill",
                                accessibilityLabel: "Light rain starts around 10 AM",
                                isPrecipitationStart: true
                            ),
                            HomeWeatherChartMarker(
                                id: "preview-rain-end",
                                position: 0.42,
                                systemImage: "cloud.sun.fill",
                                accessibilityLabel: "Precipitation ends around 1 PM",
                                isPrecipitationStart: false
                            )
                        ],
                        xAxisLabels: HomeWeatherChartData.standardXAxisLabels,
                        yAxisValues: [89, 82, 75, 68, 61],
                        minimumTemperature: 61,
                        maximumTemperature: 89
                    ),
                    precipitationSummary: "Chance of light rain in the afternoon.",
                    tomorrow: HomeWeatherTomorrowSummaryData(
                        highText: "79°",
                        lowText: "61°",
                        averageText: "73°",
                        precipitationChanceText: "35%"
                    )
                ),
                isLoading: false,
                collapseAction: {}
            )
        }
        .padding()
        .background(HomePalette.background)
    }
}
