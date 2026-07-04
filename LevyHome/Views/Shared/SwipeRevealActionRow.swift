import SwiftUI

struct SwipeRevealActionRow<Content: View>: View {
    let actionLabel: String
    let systemImage: String
    let action: () -> Void
    let content: Content

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var isRevealed = false

    private let revealWidth: CGFloat = 76

    init(
        actionLabel: String,
        systemImage: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.actionLabel = actionLabel
        self.systemImage = systemImage
        self.action = action
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.snappy(duration: 0.18)) {
                    isRevealed = false
                }

                action()
            } label: {
                VStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.bold))

                    Text(actionLabel)
                        .font(.caption2.weight(.bold))
                }
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .foregroundStyle(Color.white)
                .background(AppColors.critical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionLabel)
            .opacity(actionRevealProgress)
            .allowsHitTesting(isRevealed)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: rowOffset)
                .simultaneousGesture(revealGesture)
                .animation(.snappy(duration: 0.18), value: isRevealed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityAction(named: Text(actionLabel), action)
    }

    private var rowOffset: CGFloat {
        let baseOffset = isRevealed ? -revealWidth : 0
        return min(0, max(-revealWidth, baseOffset + dragTranslation))
    }

    private var actionRevealProgress: CGFloat {
        min(1, max(0, abs(rowOffset) / revealWidth))
    }

    private var revealGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }

                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }

                let baseOffset = isRevealed ? -revealWidth : 0
                let finalOffset = min(0, max(-revealWidth, baseOffset + value.translation.width))

                withAnimation(.snappy(duration: 0.18)) {
                    isRevealed = finalOffset < -revealWidth * 0.45
                }
            }
    }
}
