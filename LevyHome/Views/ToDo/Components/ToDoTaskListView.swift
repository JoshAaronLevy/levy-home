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

                Text("\(section.tasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)

            Divider()
                .padding(.leading, AppSpacing.large)

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
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
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

                        if task.isLinkedToFamilyCalendar {
                            ToDoInlineBadge(text: "Family", systemImage: "calendar", tone: .accent)
                        }
                    }

                    if let note = task.previewNote {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.mutedText)
                            .lineLimit(2)
                    }

                    ToDoLocationRow(text: task.locationDisplayText)
                }
                .layoutPriority(1)

                Spacer(minLength: AppSpacing.small)

                VStack(alignment: .trailing, spacing: AppSpacing.small) {
                    ToDoDueBadge(text: task.dateDisplayText, tone: task.dateTone)

                    ToDoAssigneeStack(initials: creator.map { [$0.initials] } ?? ["?"])
                }
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
