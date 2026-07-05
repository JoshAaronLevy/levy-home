import SwiftUI

struct HomeWeatherTomorrowSection: View {
    let data: HomeWeatherTomorrowSummaryData

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Label("Tomorrow", systemImage: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HomePalette.ink)

            HStack(spacing: 0) {
                HomeWeatherMetricView(title: "High", value: data.highText)
                HomeWeatherMetricDivider()
                HomeWeatherMetricView(title: "Low", value: data.lowText)
                HomeWeatherMetricDivider()
                HomeWeatherMetricView(title: "Avg", value: data.averageText)
                HomeWeatherMetricDivider()
                HomeWeatherMetricView(title: "Rain", value: data.precipitationChanceText)
            }
        }
    }
}

private struct HomeWeatherMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HomePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HomePalette.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeWeatherMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(HomePalette.hairline)
            .frame(width: 1, height: 34)
    }
}
