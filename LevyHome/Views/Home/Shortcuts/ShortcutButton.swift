import SwiftUI

struct ShortcutButton: View {
    let shortcut: AutomationShortcut
    let isBusy: Bool
    let isPerforming: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.small) {
                if isPerforming {
                    ProgressView()
                        .tint(shortcut.tone.color)
                        .frame(height: 30)
                } else {
                    Image(systemName: shortcut.systemImage)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(shortcut.tone.color)
                        .frame(height: 30)
                }

                Text(shortcut.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HomePalette.ink)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, minHeight: 18)

                Text(shortcut.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(shortcut.tone.color.opacity(shortcut.isAvailable ? 0.95 : 0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .padding(.horizontal, AppSpacing.xSmall)
            .background(HomePalette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(HomePalette.hairline, lineWidth: 1)
            }
            .shadow(color: HomePalette.shadow.opacity(0.72), radius: 14, y: 8)
            .opacity(shortcut.isAvailable ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!shortcut.isAvailable || isBusy)
        .accessibilityLabel(
            shortcut.isAvailable
                ? "\(shortcut.title), \(shortcut.subtitle)"
                : "\(shortcut.title), \(shortcut.subtitle), unavailable"
        )
    }
}
