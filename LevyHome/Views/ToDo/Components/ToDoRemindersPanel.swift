import SwiftUI

struct ToDoRemindersPanel: View {
    let state: ToDoPersonalRemindersState
    let reminders: [ToDoReminder]
    let onCompleteReminder: (ToDoReminder) -> Void
    let onSelectReminder: (ToDoReminder) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                ToDoIconBadge(systemImage: "checklist", tone: .accent)

                Text("Your Reminders")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)

            if showsContentDivider {
                Divider()
                    .padding(.leading, AppSpacing.large)
            }

            content
        }
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    private var showsContentDivider: Bool {
        switch state {
        case .synced where reminders.isEmpty:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .requestingPermission, .loading:
            HStack(spacing: AppSpacing.medium) {
                ProgressView()
                    .tint(AppColors.accent)

                Text("Syncing Reminders...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.large)
        case .permissionNeeded:
            reminderMessage(
                title: "Reminders access needed",
                detail: "Allow Reminders access to show your personal reminders.",
                systemImage: "checklist",
                actionTitle: "Try Again"
            )
        case .restricted:
            reminderMessage(
                title: "Reminders access restricted",
                detail: "This iPhone is not allowing Levy Home to read reminders.",
                systemImage: "lock.circle",
                actionTitle: nil
            )
        case .failed(let message):
            reminderMessage(
                title: "Reminders unavailable",
                detail: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Retry"
            )
        case .synced:
            if !reminders.isEmpty {
                ForEach(reminders) { reminder in
                    ToDoReminderRow(
                        reminder: reminder,
                        onComplete: {
                            onCompleteReminder(reminder)
                        },
                        onSelect: {
                            onSelectReminder(reminder)
                        }
                    )

                    if reminder.id != reminders.last?.id {
                        Divider()
                            .padding(.leading, 92)
                    }
                }
            }
        }
    }

    private func reminderMessage(
        title: String,
        detail: String,
        systemImage: String,
        actionTitle: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                ToDoIconBadge(systemImage: systemImage, tone: state.statusTone)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle {
                Button(action: onRetry) {
                    Label(actionTitle, systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.large)
    }
}

private struct ToDoReminderRow: View {
    let reminder: ToDoReminder
    let onComplete: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(reminder.dueTone.foregroundColor)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete reminder")

            VStack(spacing: 2) {
                Text(reminder.dueBadgeTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(reminder.dueTone.foregroundColor)

                Text(reminder.dueBadgeSubtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
            }
            .frame(width: 42)

            Text(reminder.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)
                .padding(.top, AppSpacing.xSmall)
                .frame(width: 18)
        }
        .padding(AppSpacing.medium)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
    }
}

struct ToDoReminderDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reminder: ToDoReminder

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    ToDoFormPanel(title: "Reminder", systemImage: "checklist") {
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(reminder.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(reminder.dueDetailText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(reminder.dueTone.foregroundColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ToDoFormPanel(title: "Details", systemImage: "info.circle") {
                        ToDoCalendarDetailRow(title: "List", value: reminder.listTitle, systemImage: "list.bullet")
                        ToDoCalendarDetailRow(title: "Due", value: reminder.dueDetailText, systemImage: "calendar")
                        ToDoCalendarDetailRow(title: "Priority", value: reminder.priorityText, systemImage: "exclamationmark.circle")

                        if let urlText = reminder.url?.absoluteString, !urlText.isEmpty {
                            ToDoCalendarDetailRow(title: "URL", value: urlText, systemImage: "link")
                        }
                    }

                    if let notes = reminder.notes, !notes.isEmpty {
                        ToDoFormPanel(title: "Notes", systemImage: "note.text") {
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(AppSpacing.screen)
                .padding(.bottom, AppSpacing.xLarge)
            }
            .background(AppColors.pageBackground)
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
