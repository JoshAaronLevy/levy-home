import SwiftUI

struct AutomationShortcutStrip: View {
    let shortcuts: [AutomationShortcut]
    let isBusy: Bool
    let performingActionID: String?
    let onActionSelected: (QuickActionDisplayData) -> Void

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.small),
                    GridItem(.flexible(), spacing: AppSpacing.small),
                    GridItem(.flexible(), spacing: AppSpacing.small),
                    GridItem(.flexible(), spacing: AppSpacing.small)
                ],
                spacing: AppSpacing.small
            ) {
                ForEach(shortcuts) { shortcut in
                    ShortcutButton(
                        shortcut: shortcut,
                        isBusy: isBusy,
                        isPerforming: isPerforming(shortcut)
                    ) {
                        if let action = shortcut.action {
                            onActionSelected(action)
                        }
                    }
                }
            }

            HStack(spacing: AppSpacing.xSmall) {
                Circle()
                    .fill(HomePalette.blue)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(HomePalette.hairline)
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(HomePalette.hairline)
                    .frame(width: 8, height: 8)
            }
            .accessibilityHidden(true)
        }
    }

    private func isPerforming(_ shortcut: AutomationShortcut) -> Bool {
        guard let action = shortcut.action, let performingActionID else {
            return false
        }

        return action.id == performingActionID
    }
}
