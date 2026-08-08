import SwiftUI

struct RecentActivityRibbon: View {
    let events: [LevyHomeEvent]
    let hasLoadedEvents: Bool
    var now: () -> Date = Date.init

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Text("Today's Activity")
                    .font(.headline)
                    .foregroundStyle(HomePalette.ink)
            }

            VStack(spacing: 0) {
                if hasLoadedEvents && events.isEmpty {
                    ActivityRibbonRow(icon: "clock", tone: .neutral, title: "No activity or alerts yet", detail: "")
                } else {
                    ForEach(events) { event in
                        ActivityRibbonRow(
                            icon: icon(for: event),
                            tone: tone(for: event.display.severity),
                            title: event.display.title,
                            detail: elapsedTime(for: event)
                        )
                    }
                }
            }
        }
        .padding(AppSpacing.large)
        .background(HomePalette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(HomePalette.hairline, lineWidth: 1)
        }
    }

    private func icon(for event: LevyHomeEvent) -> String {
        switch event.type {
        case .garageOpened: return "door.garage.open"
        case .garageClosed: return "door.garage.closed"
        case .garageLeftOpen10Min, .garageOpenedAfterHours, .garageStillOpenAt10PM: return "exclamationmark.triangle"
        case .partnerLeftHome, .partnerArrivedHome: return "person.2"
        case .studyLightsOn: return "lightbulb"
        case .doorbellPressed: return "bell"
        case .doorbellPersonDetected: return "person.crop.circle"
        case .doorbellMotionDetected: return "figure.walk.motion"
        case .phoneStateChanged: return "iphone"
        case .thermostatSetpointHigh: return "thermometer.medium"
        case .unknown: return "clock"
        }
    }

    private func elapsedTime(for event: LevyHomeEvent) -> String {
        guard let date = Self.isoFormatterWithFractionalSeconds.date(from: event.occurredAt) ?? Self.isoFormatter.date(from: event.occurredAt) else {
            return ""
        }

        let elapsedMinutes = max(0, Int(now().timeIntervalSince(date) / 60))
        if elapsedMinutes < 60 { return "\(elapsedMinutes)m ago" }
        return "\(elapsedMinutes / 60)h ago"
    }

    private func tone(for severity: DisplaySeverity) -> StatusBadgeTone {
        switch severity {
        case .info: return .accent
        case .warning: return .warning
        case .critical: return .critical
        case .unknown: return .neutral
        }
    }

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
