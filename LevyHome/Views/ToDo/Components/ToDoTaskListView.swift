import SwiftUI

struct ToDoTaskSectionView: View {
    let section: ToDoTaskSection
    let usersById: [Int: LevyHomeUser]
    let onToggleCompletion: (ToDoTask) -> Void
    let onEdit: (ToDoTask) -> Void
    let onDelete: (ToDoTask) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                ToDoIconBadge(systemImage: section.systemImage, tone: section.tone)

                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)

            Divider()
                .padding(.leading, AppSpacing.large)

            if section.tasks.isEmpty {
                ToDoTaskEmptyState()
            } else {
                ForEach(section.tasks) { task in
                    ToDoTaskRow(
                        task: task,
                        creator: task.createdBy.flatMap { usersById[$0] }
                    ) {
                        onToggleCompletion(task)
                    } onEdit: {
                        onEdit(task)
                    } onDelete: {
                        onDelete(task)
                    }

                    if task.id != section.tasks.last?.id {
                        Divider()
                            .padding(.leading, 62)
                    }
                }
            }
        }
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ToDoTaskEmptyState: View {
    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            ToDoIconBadge(systemImage: "checkmark.circle", tone: .success)

            Text("No To Do items")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(AppSpacing.large)
    }
}

private struct ToDoTaskRow: View {
    let task: ToDoTask
    let creator: LevyHomeUser?
    let onToggleCompletion: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SwipeRevealActionRow(
            actionLabel: "Delete",
            systemImage: "trash",
            action: onDelete
        ) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Button(action: onToggleCompletion) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(task.isCompleted ? AppColors.success : AppColors.accent)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "Reopen to do" : "Complete to do")

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                        Text(task.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(task.isCompleted ? AppColors.mutedText : .primary)
                            .strikethrough(task.isCompleted, color: AppColors.mutedText)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        if task.isLinkedToFamilyCalendar {
                            ToDoInlineBadge(text: "Family", systemImage: "calendar", tone: .accent)
                        }
                    }

                    Text(task.dueListDisplayText)
                        .font(.subheadline)
                        .foregroundStyle(task.dateTone.foregroundColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: AppSpacing.small) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.mutedText)
                        .frame(width: 18, height: 18)

                    ToDoAssigneeStack(initials: creator.map { [$0.initials] } ?? ["?"])
                }
                .frame(width: 30)
            }
            .padding(AppSpacing.medium)
            .background(AppColors.panelBackground)
            .opacity(task.isCompleted ? 0.72 : 1)
            .accessibilityElement(children: .combine)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            .contextMenu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
