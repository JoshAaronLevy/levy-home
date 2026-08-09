import SwiftUI

struct EventCardView: View {
    let event: LevyHomeEvent
    var dateFormatter = DateFormattingService()

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(event.display.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(event.display.body)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: AppSpacing.small) {
                SeverityBadgeView(severity: event.display.severity)

                Text(dateFormatter.displayString(for: event.occurredAt))
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                metadataRow(label: "Entity", value: event.entityId)

                if let source = event.source, !source.isEmpty {
                    metadataRow(label: "Source", value: source)
                }

                if let pushMessage {
                    metadataRow(label: "Push", value: pushMessage)
                }
            }
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    private var iconName: String {
        switch event.type {
        case .garageOpened:
            return "door.garage.open"
        case .garageClosed:
            return "door.garage.closed"
        case .garageLeftOpen10Min, .garageOpenedAfterHours, .garageStillOpenAt10PM:
            return "exclamationmark.triangle"
        case .partnerLeftHome, .partnerArrivedHome:
            return "person.2"
        case .studyLightsOn:
            return "lightbulb"
        case .doorbellPressed:
            return "bell"
        case .doorbellPersonDetected:
            return "person.crop.circle"
        case .doorbellMotionDetected:
            return "figure.walk.motion"
        case .phoneStateChanged:
            return "iphone"
        case .thermostatSetpointHigh:
            return "thermometer.medium"
        case .unknown:
            return "clock"
        }
    }

    private var iconColor: Color {
        switch event.display.severity {
        case .info:
            return AppColors.accent
        case .warning:
            return AppColors.warning
        case .critical:
            return AppColors.critical
        case .unknown:
            return AppColors.mutedText
        }
    }

    private var pushMessage: String? {
        guard let push = event.push else {
            return nil
        }

        if push.skipped {
            return push.reason ?? "Skipped"
        }

        if push.attempted {
            return "Sent"
        }

        return nil
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)
                .frame(width: 48, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(AppColors.mutedText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }
}

#Preview {
    EventCardView(
        event: LevyHomeEvent(
            id: "event-1",
            type: .garageLeftOpen10Min,
            entityId: "cover.main_garage_door",
            category: .garage,
            severity: .high,
            source: "home_assistant",
            occurredAt: "2026-06-12T14:00:00Z",
            title: "Garage left open",
            message: "The garage has been open for 10 minutes.",
            receivedAt: "2026-06-12T14:00:01Z",
            display: EventDisplayMetadata(
                title: "Garage left open",
                body: "The garage has been open for 10 minutes.",
                severity: .warning
            ),
            push: EventPushStatus(
                attempted: true,
                skipped: false,
                reason: nil,
                ticketCount: 1,
                invalidTokenCount: 0
            )
        )
    )
    .padding()
    .background(AppColors.pageBackground)
}
