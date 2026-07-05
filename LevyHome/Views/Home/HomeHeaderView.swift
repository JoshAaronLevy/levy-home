import SwiftUI

struct HomeHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Levy Home")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(HomePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: AppSpacing.medium)

                HStack(spacing: AppSpacing.medium) {
                    /*
                    TODO: Restore after alerts are fine-tuned and notifications are ready.
                    Button {} label: {
                        Image(systemName: "bell")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(HomePalette.ink)
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(HomePalette.coral)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 2, y: -2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Notifications")
                    */

                    HomeAvatarView()
                }
            }
        }
    }
}

private struct HomeAvatarView: View {
    var body: some View {
        Image("HomeAvatar")
            .resizable()
            .scaledToFill()
            .frame(width: 76, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.88), lineWidth: 3)
            }
            .shadow(color: HomePalette.shadow, radius: 11, y: 6)
            .accessibilityLabel("Home profile")
    }
}
