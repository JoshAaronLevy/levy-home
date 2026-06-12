import SwiftUI

enum BannerTone: Equatable {
    case info
    case success
    case warning
    case error

    var iconName: String {
        switch self {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .info:
            return AppColors.accent
        case .success:
            return AppColors.success
        case .warning:
            return AppColors.warning
        case .error:
            return AppColors.critical
        }
    }

    var backgroundColor: Color {
        switch self {
        case .info:
            return AppColors.accentSoft
        case .success:
            return AppColors.successSoft
        case .warning:
            return AppColors.warningSoft
        case .error:
            return AppColors.criticalSoft
        }
    }
}

struct ErrorBannerView: View {
    let message: String
    var tone: BannerTone = .error

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: tone.iconName)
                .font(.headline)
                .foregroundStyle(tone.foregroundColor)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.medium)
        .background(tone.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
    }
}

#Preview {
    VStack(spacing: AppSpacing.medium) {
        ErrorBannerView(message: "The API returned an unexpected response.")
        ErrorBannerView(message: "Live data is not connected yet.", tone: .info)
    }
    .padding()
}
