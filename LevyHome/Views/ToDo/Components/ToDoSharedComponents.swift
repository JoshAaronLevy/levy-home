import SwiftUI

struct ToDoAvatarStack: View {
    let initials: [String]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(initials.enumerated()), id: \.offset) { index, initial in
                Text(initial)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(index == 0 ? Color.white : AppColors.accent)
                    .frame(width: 30, height: 30)
                    .background(index == 0 ? AppColors.accent : AppColors.accentSoft)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(AppColors.panelBackground, lineWidth: 2)
                    }
                    .zIndex(Double(initials.count - index))
            }
        }
    }
}

struct ToDoAssigneeStack: View {
    let initials: [String]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(initials.prefix(2).enumerated()), id: \.offset) { index, initial in
                Text(initial)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(index == 0 ? Color.white : AppColors.accent)
                    .frame(width: 24, height: 24)
                    .background(index == 0 ? AppColors.accent : AppColors.accentSoft)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(AppColors.panelBackground, lineWidth: 2)
                    }
                    .zIndex(Double(initials.count - index))
            }
        }
    }
}

struct ToDoStatusPill: View {
    let text: String
    let systemImage: String
    let tone: ToDoTone

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))

            Text(text)
                .font(.caption.weight(.semibold))
        }
        .lineLimit(1)
        .padding(.horizontal, AppSpacing.small)
        .frame(height: 28)
        .foregroundStyle(tone.foregroundColor)
        .background(tone.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
    }
}

struct ToDoInlineBadge: View {
    let text: String
    let systemImage: String
    let tone: ToDoTone

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))

            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .lineLimit(1)
        .padding(.horizontal, AppSpacing.xSmall)
        .frame(height: 20)
        .foregroundStyle(tone.foregroundColor)
        .background(tone.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ToDoDueBadge: View {
    let text: String
    let tone: ToDoTone

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.small)
            .frame(height: 26)
            .foregroundStyle(tone.foregroundColor)
            .background(tone.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
    }
}

struct ToDoIconBadge: View {
    let systemImage: String
    let tone: ToDoTone

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tone.foregroundColor)
            .frame(width: 30, height: 30)
            .background(tone.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
    }
}

struct ToDoLocationRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
            Image(systemName: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColors.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
