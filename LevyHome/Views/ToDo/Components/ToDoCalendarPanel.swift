import SwiftUI

struct ToDoCalendarPanel: View {
    let state: ToDoFamilyCalendarState
    let events: [ToDoCalendarEvent]
    let onToggleCompletion: (ToDoCalendarEvent) -> Void
    let onSelectEvent: (ToDoCalendarEvent) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                ToDoIconBadge(systemImage: "calendar", tone: .accent)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Today")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Family calendar")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                }

                Spacer()

                ToDoStatusPill(
                    text: state.statusText(eventCount: events.count),
                    systemImage: state.statusSystemImage(eventCount: events.count),
                    tone: state.statusTone
                )
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
        case .synced where events.isEmpty:
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

                Text("Syncing Family Calendar...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.large)
        case .permissionNeeded:
            calendarMessage(
                title: "Calendar access needed",
                detail: "Allow calendar access to show today's Family Calendar events.",
                systemImage: "calendar.badge.exclamationmark",
                actionTitle: "Try Again"
            )
        case .restricted:
            calendarMessage(
                title: "Calendar access restricted",
                detail: "This iPhone is not allowing Levy Home to read calendar events.",
                systemImage: "lock.circle",
                actionTitle: nil
            )
        case .calendarNotFound:
            calendarMessage(
                title: "Family Calendar not found",
                detail: "No calendar named Family was found on this iPhone.",
                systemImage: "calendar.badge.exclamationmark",
                actionTitle: nil
            )
        case .failed(let message):
            calendarMessage(
                title: "Family Calendar unavailable",
                detail: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Retry"
            )
        case .synced:
            if !events.isEmpty {
                ForEach(events) { event in
                    ToDoCalendarEventRow(
                        event: event,
                        onToggleCompletion: {
                            onToggleCompletion(event)
                        },
                        onSelect: {
                            onSelectEvent(event)
                        }
                    )

                    if event.id != events.last?.id {
                        Divider()
                            .padding(.leading, 92)
                    }
                }
            }
        }
    }

    private func calendarMessage(
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

private struct ToDoCalendarEventRow: View {
    let event: ToDoCalendarEvent
    let onToggleCompletion: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Button(action: onToggleCompletion) {
                Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(event.isCompleted ? AppColors.success : AppColors.accent)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.isCompleted ? "Mark calendar event not done" : "Mark calendar event done")

            VStack(spacing: 2) {
                Text(event.time)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(event.isCompleted ? AppColors.mutedText : AppColors.accent)

                Text(event.period)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Text(event.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(event.isCompleted ? AppColors.mutedText : .primary)
                        .strikethrough(event.isCompleted, color: AppColors.mutedText)
                        .lineLimit(2)

                    if event.isCompleted {
                        ToDoInlineBadge(text: "Done", systemImage: "checkmark.circle.fill", tone: .success)
                    }
                }

                ToDoLocationRow(text: event.locationDisplayText)
            }

            Spacer(minLength: AppSpacing.small)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)
                .padding(.top, AppSpacing.xSmall)
        }
        .padding(AppSpacing.medium)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
    }
}

struct ToDoCalendarEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: ToDoCalendarEvent

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    ToDoFormPanel(title: "Event", systemImage: "calendar") {
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            Text(event.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(event.timeRangeText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ToDoFormPanel(title: "Details", systemImage: "info.circle") {
                        ToDoCalendarDetailRow(title: "Calendar", value: event.calendarTitle, systemImage: "calendar")
                        ToDoCalendarDetailRow(title: "Status", value: event.isCompleted ? "Done in Levy Home" : "Not done", systemImage: event.isCompleted ? "checkmark.circle.fill" : "circle")
                        ToDoCalendarDetailRow(title: "Location", value: event.locationDisplayText, systemImage: "mappin.and.ellipse")

                        if let urlText = event.url?.absoluteString, !urlText.isEmpty {
                            ToDoCalendarDetailRow(title: "URL", value: urlText, systemImage: "link")
                        }
                    }

                    if let notes = event.notes, !notes.isEmpty {
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
            .navigationTitle("Calendar Event")
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

struct ToDoCalendarDetailRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
