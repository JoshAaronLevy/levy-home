import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.headline)
                }

                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(isDisabled || isLoading ? AppColors.disabledControl : AppColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: AppSpacing.medium) {
        PrimaryActionButton(title: "Turn Off Lights", systemImage: "lightbulb.slash") {}
        PrimaryActionButton(title: "Closing Garage", systemImage: "door.garage.closed", isLoading: true) {}
        PrimaryActionButton(title: "Action Unavailable", systemImage: "bolt.slash", isDisabled: true) {}
    }
    .padding()
}
