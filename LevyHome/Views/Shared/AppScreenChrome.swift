import SwiftUI

struct AppScreenHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.large) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppColors.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: AppSpacing.small)

            accessory
        }
    }
}

extension AppScreenHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct AppHeaderIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AppColors.text)
                .frame(width: 58, height: 58)
                .background(AppColors.panelBackground, in: Circle())
                .overlay {
                    Circle()
                        .stroke(AppColors.panelBorder, lineWidth: 1)
                }
                .shadow(color: AppColors.surfaceShadow.opacity(0.45), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct AppHeaderControlGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.horizontal, AppSpacing.small)
        .frame(height: 58)
        .background(AppColors.panelBackground, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
        .shadow(color: AppColors.surfaceShadow.opacity(0.45), radius: 12, y: 6)
    }
}

struct AppHeaderGroupedButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AppColors.text)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    func appScreenChrome() -> some View {
        self
            .background(AppColors.pageBackground.ignoresSafeArea())
            .preferredColorScheme(.light)
            .toolbar(.hidden, for: .navigationBar)
    }
}
