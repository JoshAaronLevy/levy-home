import ActivityKit
import Foundation
import SwiftUI
import UIKit
import WidgetKit

struct ShoppingTripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingTripActivityAttributes.self) { context in
            ShoppingTripLockScreenView(context: context)
                .activityBackgroundTint(Color(uiColor: .systemBackground))
                .activitySystemActionForegroundColor(Color.primary)
                .widgetURL(ShoppingTripPresentation.deepLink(for: context.attributes.tripID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ShoppingTripExpandedMetric(
                        value: context.state.pickedUpCount,
                        label: "picked up",
                        accessibilityLabel: ShoppingTripPresentation.pickedUpAccessibilityLabel(
                            context.state.pickedUpCount
                        )
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ShoppingTripExpandedMetric(
                        value: context.state.remainingCount,
                        label: "left",
                        accessibilityLabel: ShoppingTripPresentation.remainingAccessibilityLabel(
                            context.state.remainingCount
                        )
                    )
                }

                DynamicIslandExpandedRegion(.center) {
                    Label(
                        ShoppingTripPresentation.title(for: context.state),
                        systemImage: context.state.isCompleted ? "checkmark.circle.fill" : "cart.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShoppingTripPresentation.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(ShoppingTripPresentation.title(for: context.state))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ShoppingTripExpandedBottomView(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
            } compactLeading: {
                Image(systemName: context.state.isCompleted ? "checkmark" : "cart.fill")
                    .foregroundStyle(ShoppingTripPresentation.accentColor)
                    .accessibilityLabel(ShoppingTripPresentation.title(for: context.state))
            } compactTrailing: {
                Text(ShoppingTripPresentation.compactCount(context.state.remainingCount, limit: 999))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityLabel(
                        ShoppingTripPresentation.remainingAccessibilityLabel(
                            context.state.remainingCount
                        )
                    )
            } minimal: {
                Text(ShoppingTripPresentation.compactCount(context.state.remainingCount, limit: 99))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(
                        "Shopping trip, "
                            + ShoppingTripPresentation.remainingAccessibilityLabel(
                                context.state.remainingCount
                            )
                    )
            }
            .widgetURL(ShoppingTripPresentation.deepLink(for: context.attributes.tripID))
            .keylineTint(ShoppingTripPresentation.accentColor)
        }
    }
}

private struct ShoppingTripLockScreenView: View {
    let context: ActivityViewContext<ShoppingTripActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(
                    ShoppingTripPresentation.title(for: context.state),
                    systemImage: context.state.isCompleted ? "checkmark.circle.fill" : "cart.fill"
                )
                .font(.headline.weight(.semibold))
                .foregroundStyle(ShoppingTripPresentation.accentColor)
                .lineLimit(1)

                Spacer(minLength: 8)

                Text(context.state.isCompleted ? "Done" : "Live")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ShoppingTripPresentation.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ShoppingTripPresentation.accentColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            Text(ShoppingTripPresentation.statusLine(for: context.state))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)

            Text("Est. \(ShoppingTripPresentation.estimatedAmount(for: context.state))")
                .font(.title2.weight(.bold))
                .foregroundStyle(ShoppingTripPresentation.accentColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)

            if context.state.unpricedPickedItemCount > 0 {
                Text(
                    ShoppingTripPresentation.unpricedNote(
                        count: context.state.unpricedPickedItemCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            Text("Started by \(context.attributes.startedByName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ShoppingTripPresentation.accessibilityDescription(
                attributes: context.attributes,
                state: context.state
            )
        )
    }
}

private struct ShoppingTripExpandedMetric: View {
    let value: Int
    let label: String
    let accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(max(0, value))")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ShoppingTripExpandedBottomView: View {
    let attributes: ShoppingTripActivityAttributes
    let state: ShoppingTripActivityState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Est. \(ShoppingTripPresentation.estimatedAmount(for: state))")
                .font(.headline.weight(.bold))
                .foregroundStyle(ShoppingTripPresentation.accentColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 4)

            if state.unpricedPickedItemCount > 0 {
                Text("\(state.unpricedPickedItemCount) unpriced")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("by \(attributes.startedByName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ShoppingTripPresentation.expandedBottomAccessibilityLabel(
                attributes: attributes,
                state: state
            )
        )
    }
}

private enum ShoppingTripPresentation {
    static let accentColor = Color(uiColor: .systemGreen)

    static func title(for state: ShoppingTripActivityState) -> String {
        state.isCompleted ? "Shopping Complete" : "Shopping Trip"
    }

    static func statusLine(for state: ShoppingTripActivityState) -> String {
        "\(max(0, state.pickedUpCount)) picked up • \(max(0, state.remainingCount)) left"
    }

    static func estimatedAmount(for state: ShoppingTripActivityState) -> String {
        let currencyCode = state.currencyCode.isEmpty ? "USD" : state.currencyCode
        let amount = Decimal(max(0, state.estimatedTotalCents)) / Decimal(100)
        return amount.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(2))
        )
    }

    static func compactCount(_ count: Int, limit: Int) -> String {
        let safeCount = max(0, count)
        return safeCount > limit ? "\(limit)+" : "\(safeCount)"
    }

    static func pickedUpAccessibilityLabel(_ count: Int) -> String {
        let safeCount = max(0, count)
        return "\(safeCount) \(safeCount == 1 ? "item" : "items") picked up"
    }

    static func remainingAccessibilityLabel(_ count: Int) -> String {
        let safeCount = max(0, count)
        return "\(safeCount) \(safeCount == 1 ? "item" : "items") left"
    }

    static func unpricedNote(count: Int) -> String {
        let safeCount = max(0, count)
        return "\(safeCount) picked \(safeCount == 1 ? "item has" : "items have") no price"
    }

    static func accessibilityDescription(
        attributes: ShoppingTripActivityAttributes,
        state: ShoppingTripActivityState
    ) -> String {
        var parts = [
            title(for: state),
            pickedUpAccessibilityLabel(state.pickedUpCount),
            remainingAccessibilityLabel(state.remainingCount),
            "Estimated total \(estimatedAmount(for: state))"
        ]

        if state.unpricedPickedItemCount > 0 {
            parts.append(unpricedNote(count: state.unpricedPickedItemCount))
        }

        parts.append("Started by \(attributes.startedByName)")
        return parts.joined(separator: ". ")
    }

    static func expandedBottomAccessibilityLabel(
        attributes: ShoppingTripActivityAttributes,
        state: ShoppingTripActivityState
    ) -> String {
        var parts = ["Estimated total \(estimatedAmount(for: state))"]

        if state.unpricedPickedItemCount > 0 {
            parts.append(unpricedNote(count: state.unpricedPickedItemCount))
        } else {
            parts.append("Started by \(attributes.startedByName)")
        }

        return parts.joined(separator: ". ")
    }

    static func deepLink(for tripID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "levyhome"
        components.host = "shopping"
        components.queryItems = [URLQueryItem(name: "trip", value: tripID)]
        return components.url
    }
}
