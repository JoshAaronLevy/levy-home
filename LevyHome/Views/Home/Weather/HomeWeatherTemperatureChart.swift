import SwiftUI

struct HomeWeatherTemperatureChart: View {
    let data: HomeWeatherChartData

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Label("Temperature", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomePalette.ink)

                Spacer()
            }

            HStack(alignment: .top, spacing: AppSpacing.small) {
                VStack(alignment: .trailing) {
                    ForEach(Array(data.yAxisValues.enumerated()), id: \.offset) { _, value in
                        Text("\(value)°")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HomePalette.secondaryInk)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 34, height: 136)

                VStack(spacing: AppSpacing.small) {
                    HomeWeatherChartPlot(data: data)
                        .frame(height: 136)

                    HomeWeatherChartXAxis(data: data)
                        .frame(height: 16)
                }
            }
        }
    }
}

private struct HomeWeatherChartPlot: View {
    let data: HomeWeatherChartData

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(data.yAxisValues.indices, id: \.self) { index in
                    Rectangle()
                        .fill(HomePalette.hairline)
                        .frame(height: 1)
                        .position(
                            x: proxy.size.width / 2,
                            y: yPosition(forIndex: index, count: data.yAxisValues.count, height: proxy.size.height)
                        )
                }

                if data.points.count > 1 {
                    Path { path in
                        guard let firstPoint = data.points.first else {
                            return
                        }

                        path.move(to: point(for: firstPoint, size: proxy.size))

                        for chartPoint in data.points.dropFirst() {
                            path.addLine(to: point(for: chartPoint, size: proxy.size))
                        }
                    }
                    .stroke(HomePalette.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                ForEach(data.points) { chartPoint in
                    Circle()
                        .fill(HomePalette.gold)
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle()
                                .stroke(HomePalette.surface, lineWidth: 2)
                        }
                        .position(point(for: chartPoint, size: proxy.size))
                }

                if data.points.isEmpty {
                    Text("Forecast unavailable")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomePalette.secondaryInk)
                }
            }
        }
    }

    private func yPosition(forIndex index: Int, count: Int, height: CGFloat) -> CGFloat {
        guard count > 1 else {
            return height / 2
        }

        return CGFloat(index) / CGFloat(count - 1) * height
    }

    private func point(for chartPoint: HomeWeatherChartPoint, size: CGSize) -> CGPoint {
        let span = max(data.maximumTemperature - data.minimumTemperature, 1)
        let normalizedY = (data.maximumTemperature - chartPoint.temperature) / span

        return CGPoint(
            x: chartPoint.position * size.width,
            y: min(max(normalizedY, 0), 1) * size.height
        )
    }
}

private struct HomeWeatherChartXAxis: View {
    let data: HomeWeatherChartData

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(data.xAxisLabels) { label in
                    Text(label.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HomePalette.secondaryInk)
                        .lineLimit(1)
                        .position(
                            x: min(max(label.position * proxy.size.width, 22), proxy.size.width - 22),
                            y: 8
                        )
                }
            }
        }
    }
}
