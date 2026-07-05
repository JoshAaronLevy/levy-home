import SwiftUI

struct InlineLoadingView: View {
    let message: String
    var font: Font = .body

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            ProgressView()

            Text(message)
                .font(font)
                .foregroundStyle(AppColors.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    InlineLoadingView(message: "Loading...")
        .padding()
}
