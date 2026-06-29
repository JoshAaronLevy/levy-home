import SwiftUI

struct ToDoView: View {
    @State private var isShowingAddSheet = false

    private let openTaskCount = 5
    private let dueTodayCount = 2
    private let completedTaskCount = 3
    private let events = ToDoPreviewData.calendarEvents
    private let sections = ToDoPreviewData.taskSections

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                ToDoSummaryCard(
                    openTaskCount: openTaskCount,
                    dueTodayCount: dueTodayCount,
                    completedTaskCount: completedTaskCount,
                    calendarEventCount: events.count
                )

                ToDoCalendarPanel(events: events)

                ForEach(sections) { section in
                    ToDoTaskSectionView(section: section)
                }
            }
            .padding(AppSpacing.screen)
            .padding(.bottom, AppSpacing.xLarge)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("To Do")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filter to dos")

                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add to do")
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            ToDoEditorSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ToDoSummaryCard: View {
    let openTaskCount: Int
    let dueTodayCount: Int
    let completedTaskCount: Int
    let calendarEventCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                ToDoAvatarStack(initials: ["J", "M"])

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("\(openTaskCount) open")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: AppSpacing.xSmall) {
                        Image(systemName: "calendar")
                            .font(.caption.weight(.semibold))

                        Text("Family Calendar")
                            .font(.caption.weight(.semibold))

                        Text("Synced 9:42 AM")
                            .font(.caption)
                            .foregroundStyle(AppColors.mutedText)
                    }
                    .foregroundStyle(AppColors.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }
                .layoutPriority(1)

                Spacer(minLength: AppSpacing.small)

                ToDoMetricPill(
                    title: "\(dueTodayCount)",
                    subtitle: "today",
                    systemImage: "clock",
                    tone: .warning
                )
            }

            ProgressView(value: Double(completedTaskCount), total: Double(completedTaskCount + openTaskCount))
                .tint(AppColors.success)

            HStack(spacing: AppSpacing.small) {
                ToDoStatusPill(
                    text: "\(completedTaskCount) done",
                    systemImage: "checkmark.circle.fill",
                    tone: .success
                )

                ToDoStatusPill(
                    text: "\(calendarEventCount) events today",
                    systemImage: "calendar",
                    tone: .accent
                )
            }
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ToDoCalendarPanel: View {
    let events: [ToDoCalendarEvent]

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

                ToDoStatusPill(text: "Synced", systemImage: "checkmark.circle.fill", tone: .success)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)

            Divider()
                .padding(.leading, AppSpacing.large)

            ForEach(events) { event in
                ToDoCalendarEventRow(event: event)

                if event.id != events.last?.id {
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

private struct ToDoCalendarEventRow: View {
    let event: ToDoCalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(spacing: 2) {
                Text(event.time)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.accent)

                Text(event.period)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Text(event.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if event.isLinkedToTask {
                        ToDoInlineBadge(text: "Linked", systemImage: "checkmark.circle.fill", tone: .accent)
                    }
                }

                ToDoLocationRow(text: event.location)
            }

            Spacer(minLength: AppSpacing.small)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)
                .padding(.top, AppSpacing.xSmall)
        }
        .padding(AppSpacing.medium)
        .accessibilityElement(children: .combine)
    }
}

private struct ToDoTaskSectionView: View {
    let section: ToDoTaskSection

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
                ToDoTaskRow(task: task)

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

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(task.isComplete ? AppColors.success : AppColors.accent)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(task.isComplete ? AppColors.mutedText : .primary)
                        .strikethrough(task.isComplete, color: AppColors.mutedText)
                        .lineLimit(2)

                    if task.isLinkedToFamilyCalendar {
                        ToDoInlineBadge(text: "Family", systemImage: "calendar", tone: .accent)
                    }
                }

                if let note = task.note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .lineLimit(2)
                }

                ToDoLocationRow(text: task.location)
            }
            .layoutPriority(1)

            Spacer(minLength: AppSpacing.small)

            VStack(alignment: .trailing, spacing: AppSpacing.small) {
                ToDoDueBadge(text: task.dueText, tone: task.dueTone)

                ToDoAssigneeStack(initials: task.assigneeInitials)
            }
        }
        .padding(AppSpacing.medium)
        .opacity(task.isComplete ? 0.72 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct ToDoAvatarStack: View {
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

private struct ToDoAssigneeStack: View {
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

private struct ToDoMetricPill: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tone: ToDoTone

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.bold))

                Text(subtitle)
                    .font(.caption2.weight(.semibold))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, AppSpacing.small)
        .frame(height: 38)
        .foregroundStyle(tone.foregroundColor)
        .background(tone.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
    }
}

private struct ToDoStatusPill: View {
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

private struct ToDoInlineBadge: View {
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

private struct ToDoDueBadge: View {
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

private struct ToDoIconBadge: View {
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

private struct ToDoLocationRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
            Image(systemName: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColors.mutedText)
                .lineLimit(2)
        }
    }
}

private struct ToDoEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ToDoDraft()

    private let categories = ToDoPreviewData.categories
    private let assignees = ToDoPreviewData.assignees
    private let recentLocations = ToDoPreviewData.recentLocations
    private let dueDateOptions = ToDoPreviewData.dueDateOptions

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    titleSection
                    categorySection
                    detailsSection
                    locationSection
                    summarySection

                    PrimaryActionButton(
                        title: "Add To Do",
                        systemImage: "plus"
                    ) {
                        dismiss()
                    }
                }
                .padding(AppSpacing.screen)
                .padding(.bottom, AppSpacing.xLarge)
            }
            .background(AppColors.pageBackground)
            .navigationTitle("New To Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var titleSection: some View {
        ToDoFormPanel(title: "Task", systemImage: "checklist") {
            ToDoTextFieldRow(
                title: "Title",
                systemImage: "text.cursor",
                text: $draft.title,
                prompt: "What needs doing?"
            )
        }
    }

    private var categorySection: some View {
        ToDoFormPanel(title: "Category", systemImage: "folder") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.small),
                    GridItem(.flexible(), spacing: AppSpacing.small)
                ],
                spacing: AppSpacing.small
            ) {
                ForEach(categories) { category in
                    ToDoChoiceButton(
                        title: category.title,
                        systemImage: category.systemImage,
                        isSelected: draft.categoryID == category.id,
                        tone: category.tone
                    ) {
                        draft.categoryID = category.id
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        ToDoFormPanel(title: "Details", systemImage: "slider.horizontal.3") {
            VStack(spacing: 0) {
                ToDoAssigneePicker(
                    assignees: assignees,
                    selectedAssigneeIDs: $draft.assigneeIDs
                )

                Divider()
                    .padding(.leading, 42)
                    .padding(.vertical, AppSpacing.medium)

                ToDoDueDatePicker(
                    dueDateOptions: dueDateOptions,
                    selectedDueDateID: $draft.dueDateID
                )

                Divider()
                    .padding(.leading, 42)
                    .padding(.vertical, AppSpacing.medium)

                ToDoToggleRow(
                    title: "Add to Family Calendar",
                    subtitle: "Creates a calendar event when saved",
                    systemImage: "calendar.badge.plus",
                    isOn: $draft.addToFamilyCalendar
                )
            }
        }
    }

    private var locationSection: some View {
        ToDoFormPanel(title: "Location", systemImage: "mappin.and.ellipse") {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                ToDoTextFieldRow(
                    title: "Place or address",
                    systemImage: "mappin.and.ellipse",
                    text: $draft.location,
                    prompt: "Add a location"
                )

                if isNewLocation {
                    ToDoInlineBadge(text: "New location", systemImage: "plus.circle.fill", tone: .accent)
                }

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.mutedText)

                    FlowLayout(spacing: AppSpacing.small, rowSpacing: AppSpacing.small) {
                        ForEach(recentLocations) { location in
                            Button {
                                draft.location = location.title
                                draft.saveLocation = false
                            } label: {
                                HStack(spacing: AppSpacing.xSmall) {
                                    Image(systemName: location.systemImage)
                                        .font(.caption.weight(.semibold))

                                    Text(location.title)
                                        .font(.caption.weight(.semibold))
                                }
                                .lineLimit(1)
                                .padding(.horizontal, AppSpacing.small)
                                .frame(height: 30)
                                .foregroundStyle(AppColors.accent)
                                .background(AppColors.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ToDoCheckboxRow(
                    title: "Save this location",
                    subtitle: "Use again for future to dos",
                    isChecked: $draft.saveLocation
                )
            }
        }
    }

    private var summarySection: some View {
        HStack(spacing: AppSpacing.medium) {
            ToDoIconBadge(systemImage: selectedCategory.systemImage, tone: selectedCategory.tone)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(draft.title.isEmpty ? "New to do" : draft.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer()

            ToDoDueBadge(text: selectedDueDate.title, tone: selectedDueDate.tone)
        }
        .padding(AppSpacing.medium)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    private var isNewLocation: Bool {
        let normalizedLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalizedLocation.isEmpty else {
            return false
        }

        return !recentLocations.contains { location in
            location.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedLocation
        }
    }

    private var selectedCategory: ToDoCategoryOption {
        categories.first { $0.id == draft.categoryID } ?? categories[0]
    }

    private var selectedDueDate: ToDoDueDateOption {
        dueDateOptions.first { $0.id == draft.dueDateID } ?? dueDateOptions[0]
    }

    private var summaryText: String {
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(selectedCategory.title) • \(selectedDueDate.title) • \(location.isEmpty ? "No location" : location)"
    }
}

private struct ToDoFormPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack(spacing: AppSpacing.medium) {
                ToDoIconBadge(systemImage: systemImage, tone: .accent)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            content
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ToDoTextFieldRow: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)

                TextField(prompt, text: $text)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textInputAutocapitalization(.words)
            }
        }
        .padding(AppSpacing.medium)
        .background(AppColors.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ToDoChoiceButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let tone: ToDoTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 42)
            .foregroundStyle(isSelected ? Color.white : tone.foregroundColor)
            .background(isSelected ? tone.foregroundColor : tone.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ToDoAssigneePicker: View {
    let assignees: [ToDoAssigneeOption]
    @Binding var selectedAssigneeIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            ToDoFormRowHeader(
                title: "Assigned to",
                subtitle: "Tap initials to include someone",
                systemImage: "person.2"
            )

            HStack(spacing: AppSpacing.small) {
                ForEach(assignees) { assignee in
                    Button {
                        toggle(assignee)
                    } label: {
                        HStack(spacing: AppSpacing.small) {
                            Text(assignee.initials)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isSelected(assignee) ? Color.white : AppColors.accent)
                                .frame(width: 28, height: 28)
                                .background(isSelected(assignee) ? AppColors.accent : AppColors.accentSoft)
                                .clipShape(Circle())

                            Text(assignee.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, AppSpacing.small)
                        .frame(height: 42)
                        .foregroundStyle(isSelected(assignee) ? .primary : AppColors.mutedText)
                        .background(AppColors.insetPanelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                                .stroke(isSelected(assignee) ? AppColors.accent : AppColors.panelBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isSelected(_ assignee: ToDoAssigneeOption) -> Bool {
        selectedAssigneeIDs.contains(assignee.id)
    }

    private func toggle(_ assignee: ToDoAssigneeOption) {
        if selectedAssigneeIDs.contains(assignee.id) {
            selectedAssigneeIDs.remove(assignee.id)
        } else {
            selectedAssigneeIDs.insert(assignee.id)
        }
    }
}

private struct ToDoDueDatePicker: View {
    let dueDateOptions: [ToDoDueDateOption]
    @Binding var selectedDueDateID: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            ToDoFormRowHeader(
                title: "Due",
                subtitle: "Choose a reminder date",
                systemImage: "clock"
            )

            FlowLayout(spacing: AppSpacing.small, rowSpacing: AppSpacing.small) {
                ForEach(dueDateOptions) { option in
                    Button {
                        selectedDueDateID = option.id
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, AppSpacing.medium)
                            .frame(height: 32)
                            .foregroundStyle(selectedDueDateID == option.id ? Color.white : option.tone.foregroundColor)
                            .background(selectedDueDateID == option.id ? option.tone.foregroundColor : option.tone.backgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ToDoToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct ToDoCheckboxRow: View {
    let title: String
    let subtitle: String
    @Binding var isChecked: Bool

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isChecked ? AppColors.accent : AppColors.mutedText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.mutedText)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(AppSpacing.medium)
        .background(AppColors.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ToDoFormRowHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
            }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    init(spacing: CGFloat = AppSpacing.small, rowSpacing: CGFloat = AppSpacing.small) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        let rows = rows(in: maxWidth, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY

        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX

            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }

            y += row.height + rowSpacing
        }
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> [FlowRow] {
        guard maxWidth > 0 else {
            return []
        }

        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = currentItems.isEmpty ? size.width : size.width + spacing

            if currentWidth + itemWidth > maxWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            currentItems.append(FlowItem(index: index, size: size))
            currentWidth += currentItems.count == 1 ? size.width : size.width + spacing
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight))
        }

        return rows
    }

    private struct FlowRow {
        let items: [FlowItem]
        let height: CGFloat
    }

    private struct FlowItem {
        let index: Int
        let size: CGSize
    }
}

private struct ToDoCalendarEvent: Identifiable {
    let id: String
    let title: String
    let time: String
    let period: String
    let location: String
    let isLinkedToTask: Bool
}

private struct ToDoTaskSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tone: ToDoTone
    let tasks: [ToDoTask]
}

private struct ToDoTask: Identifiable {
    let id: String
    let title: String
    let note: String?
    let location: String
    let dueText: String
    let dueTone: ToDoTone
    let assigneeInitials: [String]
    let isLinkedToFamilyCalendar: Bool
    let isComplete: Bool
}

private struct ToDoDraft {
    var title = "Schedule dentist"
    var categoryID = "appointments"
    var assigneeIDs: Set<String> = ["josh"]
    var dueDateID = "today"
    var addToFamilyCalendar = true
    var location = "Cherry Creek Dental"
    var saveLocation = true
}

private struct ToDoCategoryOption: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tone: ToDoTone
}

private struct ToDoAssigneeOption: Identifiable {
    let id: String
    let name: String
    let initials: String
}

private struct ToDoDueDateOption: Identifiable {
    let id: String
    let title: String
    let tone: ToDoTone
}

private struct ToDoLocationOption: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

private enum ToDoTone {
    case accent
    case success
    case warning
    case critical
    case neutral

    var foregroundColor: Color {
        switch self {
        case .accent:
            return AppColors.accent
        case .success:
            return AppColors.success
        case .warning:
            return AppColors.warning
        case .critical:
            return AppColors.critical
        case .neutral:
            return AppColors.mutedText
        }
    }

    var backgroundColor: Color {
        switch self {
        case .accent:
            return AppColors.accentSoft
        case .success:
            return AppColors.successSoft
        case .warning:
            return AppColors.warningSoft
        case .critical:
            return AppColors.criticalSoft
        case .neutral:
            return Color(uiColor: .tertiarySystemFill)
        }
    }
}

private enum ToDoPreviewData {
    static let categories = [
        ToDoCategoryOption(
            id: "appointments",
            title: "Appointments",
            systemImage: "calendar",
            tone: .accent
        ),
        ToDoCategoryOption(
            id: "house-projects",
            title: "House",
            systemImage: "wrench.and.screwdriver",
            tone: .warning
        ),
        ToDoCategoryOption(
            id: "family",
            title: "Family",
            systemImage: "person.2",
            tone: .success
        ),
        ToDoCategoryOption(
            id: "admin",
            title: "Admin",
            systemImage: "doc.text",
            tone: .neutral
        )
    ]

    static let assignees = [
        ToDoAssigneeOption(id: "josh", name: "Josh", initials: "J"),
        ToDoAssigneeOption(id: "mallory", name: "Mallory", initials: "M")
    ]

    static let dueDateOptions = [
        ToDoDueDateOption(id: "today", title: "Today", tone: .warning),
        ToDoDueDateOption(id: "tomorrow", title: "Tomorrow", tone: .accent),
        ToDoDueDateOption(id: "this-week", title: "This week", tone: .accent),
        ToDoDueDateOption(id: "none", title: "No date", tone: .neutral)
    ]

    static let recentLocations = [
        ToDoLocationOption(id: "home", title: "Home", systemImage: "house"),
        ToDoLocationOption(id: "denver-pediatrics", title: "Denver Pediatrics", systemImage: "cross.case"),
        ToDoLocationOption(id: "maple-vet-clinic", title: "Maple Vet Clinic", systemImage: "pawprint"),
        ToDoLocationOption(id: "county-office", title: "County office", systemImage: "building.columns")
    ]

    static let calendarEvents = [
        ToDoCalendarEvent(
            id: "grayson-pediatrician",
            title: "Grayson pediatrician",
            time: "2:30",
            period: "PM",
            location: "Denver Pediatrics",
            isLinkedToTask: true
        ),
        ToDoCalendarEvent(
            id: "zoe-vet-checkup",
            title: "Zoe vet checkup",
            time: "4:15",
            period: "PM",
            location: "Maple Vet Clinic",
            isLinkedToTask: false
        )
    ]

    static let taskSections = [
        ToDoTaskSection(
            id: "appointments",
            title: "Appointments",
            systemImage: "calendar",
            tone: .accent,
            tasks: [
                ToDoTask(
                    id: "schedule-dentist",
                    title: "Schedule dentist",
                    note: "Find a morning opening next week.",
                    location: "Cherry Creek Dental",
                    dueText: "Today",
                    dueTone: .warning,
                    assigneeInitials: ["J"],
                    isLinkedToFamilyCalendar: false,
                    isComplete: false
                ),
                ToDoTask(
                    id: "confirm-pediatrician",
                    title: "Confirm pediatrician paperwork",
                    note: "Bring insurance card and forms.",
                    location: "Denver Pediatrics",
                    dueText: "2:30 PM",
                    dueTone: .accent,
                    assigneeInitials: ["M"],
                    isLinkedToFamilyCalendar: true,
                    isComplete: false
                )
            ]
        ),
        ToDoTaskSection(
            id: "house-projects",
            title: "House Projects",
            systemImage: "wrench.and.screwdriver",
            tone: .warning,
            tasks: [
                ToDoTask(
                    id: "fix-gate-latch",
                    title: "Fix gate latch",
                    note: "Measure latch before hardware store run.",
                    location: "Home",
                    dueText: "Fri",
                    dueTone: .neutral,
                    assigneeInitials: ["J"],
                    isLinkedToFamilyCalendar: false,
                    isComplete: false
                )
            ]
        ),
        ToDoTaskSection(
            id: "family",
            title: "Family",
            systemImage: "person.2",
            tone: .success,
            tasks: [
                ToDoTask(
                    id: "book-summer-camp",
                    title: "Book summer camp",
                    note: "Check weekly availability.",
                    location: "Rec center",
                    dueText: "This week",
                    dueTone: .accent,
                    assigneeInitials: ["M", "J"],
                    isLinkedToFamilyCalendar: false,
                    isComplete: false
                )
            ]
        ),
        ToDoTaskSection(
            id: "admin",
            title: "Admin",
            systemImage: "doc.text",
            tone: .neutral,
            tasks: [
                ToDoTask(
                    id: "renew-passport",
                    title: "Renew passport",
                    note: "Make appointment and print forms.",
                    location: "County office",
                    dueText: "Jun 30",
                    dueTone: .critical,
                    assigneeInitials: ["J"],
                    isLinkedToFamilyCalendar: false,
                    isComplete: false
                )
            ]
        )
    ]
}

#Preview {
    NavigationStack {
        ToDoView()
    }
}
