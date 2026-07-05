import SwiftUI

struct HomeCapsuleButtonStyle: ButtonStyle {
    let tone: StatusBadgeTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, AppSpacing.large)
            .frame(height: 42)
            .foregroundStyle(tone.foregroundColor)
            .background(tone.backgroundColor, in: Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
