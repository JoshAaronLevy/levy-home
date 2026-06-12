import SwiftUI

enum StatusBadgeTone: Equatable {
    case neutral
    case accent
    case success
    case warning
    case critical

    var foregroundColor: Color {
        switch self {
        case .neutral:
            return .secondary
        case .accent:
            return AppColors.accent
        case .success:
            return AppColors.success
        case .warning:
            return AppColors.warning
        case .critical:
            return AppColors.critical
        }
    }

    var backgroundColor: Color {
        switch self {
        case .neutral:
            return Color(uiColor: .tertiarySystemFill)
        case .accent:
            return AppColors.accentSoft
        case .success:
            return AppColors.successSoft
        case .warning:
            return AppColors.warningSoft
        case .critical:
            return AppColors.criticalSoft
        }
    }
}

struct StatusBadgeView: View {
    let label: String
    var systemImage: String?
    var tone: StatusBadgeTone = .neutral

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }

            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xSmall)
        .foregroundStyle(tone.foregroundColor)
        .background(tone.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
    }
}

#Preview {
    HStack {
        StatusBadgeView(label: "Ready", systemImage: "checkmark.circle", tone: .success)
        StatusBadgeView(label: "Attention", systemImage: "exclamationmark.triangle", tone: .warning)
        StatusBadgeView(label: "Offline", systemImage: "wifi.slash", tone: .critical)
    }
    .padding()
}
