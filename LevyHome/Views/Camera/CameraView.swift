import SwiftUI

struct CameraView: View {
    private let cameraName = "Kids Room"
    private let sessionState: CameraSessionState = .placeholder

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                AppScreenHeader(title: "Camera")

                cameraPlaceholder
            }
            .padding(.horizontal, AppSpacing.screen)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, AppSpacing.xLarge * 3)
        }
        .appScreenChrome()
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: placeholderSystemImage)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(AppColors.accent)
                .frame(width: 88, height: 88)
                .background(AppColors.accentSoft, in: Circle())

            VStack(spacing: AppSpacing.small) {
                Text(cameraName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.text)

                Text("Live video and camera controls will appear here once the secure camera connection is ready.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xLarge)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cameraName) camera")
        .accessibilityValue(placeholderAccessibilityValue)
    }

    private var placeholderSystemImage: String {
        switch sessionState {
        case .placeholder, .connecting:
            "video"
        case .live:
            "video.fill"
        case .unavailable:
            "video.slash"
        }
    }

    private var placeholderAccessibilityValue: String {
        switch sessionState {
        case .placeholder:
            "Not connected"
        case .connecting:
            "Connecting"
        case .live:
            "Live"
        case let .unavailable(message):
            message
        }
    }
}

#Preview {
    NavigationStack {
        CameraView()
    }
}
