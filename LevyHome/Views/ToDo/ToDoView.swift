import EventKit
import SwiftUI

struct ToDoView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @AppStorage(ResidentPreference.storageKey) private var currentResidentName = ResidentPreference.defaultName
    @StateObject private var viewModel = ToDoViewModel()
    @StateObject private var familyCalendarViewModel = ToDoFamilyCalendarViewModel()
    @StateObject private var personalRemindersViewModel = ToDoPersonalRemindersViewModel()
    @State private var editorMode: ToDoEditorMode?
    @State private var pendingDeleteTask: ToDoTask?
    @State private var selectedCalendarEvent: ToDoCalendarEvent?
    @State private var selectedReminder: ToDoReminder?

    private var sections: [ToDoTaskSection] {
        viewModel.hasLoaded ? viewModel.sections : ToDoPreviewData.taskSections
    }

    private var users: [LevyHomeUser] {
        viewModel.users.isEmpty ? ToDoPreviewData.users : viewModel.users
    }

    private var usersById: [Int: LevyHomeUser] {
        Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    }

    private var tasks: [ToDoTask] {
        sections.flatMap(\.tasks)
    }

    private var openTaskCount: Int {
        tasks.filter { $0.status == .open }.count
    }

    private var completedTaskCount: Int {
        tasks.filter { $0.status == .completed }.count
    }

    private var dueTodayCount: Int {
        tasks.filter { task in
            task.status == .open && task.date.map(Calendar.current.isDateInToday) == true
        }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                AppScreenHeader(title: "To Do") {
                    AppHeaderControlGroup {
                        AppHeaderGroupedButton(
                            systemImage: "line.3.horizontal.decrease",
                            accessibilityLabel: "Filter to dos"
                        ) {}

                        AppHeaderGroupedButton(
                            systemImage: "plus",
                            accessibilityLabel: "Add to do"
                        ) {
                            editorMode = .add
                        }
                    }
                }

                ToDoSummaryCard(
                    openTaskCount: openTaskCount,
                    dueTodayCount: dueTodayCount,
                    completedTaskCount: completedTaskCount,
                    calendarEventCount: familyCalendarViewModel.eventCount
                )

                ToDoCalendarPanel(
                    state: familyCalendarViewModel.state,
                    events: familyCalendarViewModel.displayEvents
                ) { event in
                    familyCalendarViewModel.toggleCompletion(for: event)
                } onSelectEvent: { event in
                    selectedCalendarEvent = event
                } onRetry: {
                    Task {
                        await refreshCalendar()
                    }
                }

                ToDoRemindersPanel(
                    state: personalRemindersViewModel.state,
                    reminders: personalRemindersViewModel.displayReminders
                ) { reminder in
                    Task {
                        await personalRemindersViewModel.complete(reminder)
                    }
                } onSelectReminder: { reminder in
                    selectedReminder = reminder
                } onRetry: {
                    Task {
                        await refreshReminders()
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    ToDoErrorBanner(message: errorMessage) {
                        Task {
                            await load(force: true)
                        }
                    }
                }

                ForEach(sections) { section in
                    ToDoTaskSectionView(
                        section: section,
                        usersById: usersById
                    ) { task in
                        Task {
                            await viewModel.toggleCompletion(
                                task,
                                apiClient: appEnvironment.apiClient,
                                actor: currentActorName
                            )
                        }
                    } onEdit: { task in
                        editorMode = .edit(task)
                    } onDelete: { task in
                        pendingDeleteTask = task
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screen)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, AppSpacing.xLarge * 3)
        }
        .appScreenChrome()
        .task {
            await load()
        }
        .refreshable {
            await load(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task {
                await refreshEventKitContent()
            }
        }
        .sheet(item: $editorMode) { mode in
            ToDoEditorSheet(
                mode: mode,
                users: users,
                recentLocations: viewModel.locations.isEmpty ? ToDoPreviewData.recentLocations : viewModel.locations,
                currentUserId: viewModel.userId(for: currentResidentName)
            ) { draft in
                switch mode {
                case .add:
                    try await viewModel.createTask(
                        from: draft,
                        apiClient: appEnvironment.apiClient,
                        actor: currentActorName
                    )
                case .edit(let task):
                    try await viewModel.updateTask(
                        task,
                        from: draft,
                        apiClient: appEnvironment.apiClient,
                        actor: currentActorName
                    )
                }
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCalendarEvent) { event in
            ToDoCalendarEventDetailSheet(event: event)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedReminder) { reminder in
            ToDoReminderDetailSheet(reminder: reminder)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Delete To Do?",
            isPresented: Binding(
                get: { pendingDeleteTask != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteTask = nil
                    }
                }
            ),
            presenting: pendingDeleteTask
        ) { task in
            Button("Delete", role: .destructive) {
                Task {
                    await delete(task)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteTask = nil
            }
        } message: { task in
            Text("Remove \(task.name) from the shared to-do list.")
        }
    }

    private var currentActorName: String? {
        let trimmedName = currentResidentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private func load(force: Bool = false) async {
        await runToDoContentOperation {
            async let tasksLoad: Void = viewModel.load(apiClient: appEnvironment.apiClient, force: force)
            await loadEventKitContent(force: force)

            _ = await tasksLoad
        }
    }

    private func refreshCalendar() async {
        await runToDoContentOperation {
            await familyCalendarViewModel.loadToday(force: true)
        }
    }

    private func refreshReminders() async {
        await runToDoContentOperation {
            await personalRemindersViewModel.loadReminders(force: true)
        }
    }

    private func refreshEventKitContent() async {
        await runToDoContentOperation {
            await loadEventKitContent(force: true)
        }
    }

    private func loadEventKitContent(force: Bool) async {
        await familyCalendarViewModel.loadToday(force: force)
        await personalRemindersViewModel.loadReminders(force: force)
    }

    private func runToDoContentOperation(
        _ operation: @escaping @MainActor () async -> Void
    ) async {
        let task = Task { @MainActor in
            await operation()
        }

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            // SwiftUI can cancel view tasks around refresh gestures; keep the requested load alive.
        }
    }

    private func delete(_ task: ToDoTask) async {
        defer {
            pendingDeleteTask = nil
        }

        await viewModel.deleteTask(
            task,
            apiClient: appEnvironment.apiClient,
            actor: currentActorName
        )
    }
}

private struct ToDoErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.subheadline)
                .lineLimit(2)
                .layoutPriority(1)

            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry to-do list")
        }
        .foregroundStyle(AppColors.warning)
        .padding(AppSpacing.medium)
        .background(AppColors.warningSoft)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
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

            ProgressView(
                value: Double(completedTaskCount),
                total: Double(max(completedTaskCount + openTaskCount, 1))
            )
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

private struct ToDoTaskSectionView: View {
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
                .lineLimit(2)
        }
    }
}

private struct ToDoEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationSearch = ToDoLocationSearchViewModel()
    @State private var draft = ToDoDraft()
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    private let mode: ToDoEditorMode
    private let users: [LevyHomeUser]
    private let recentLocations: [ToDoLocation]
    private let dueDateOptions = ToDoPreviewData.dueDateOptions
    private let onSave: (ToDoDraft) async throws -> Void

    init(
        mode: ToDoEditorMode,
        users: [LevyHomeUser],
        recentLocations: [ToDoLocation],
        currentUserId: Int?,
        onSave: @escaping (ToDoDraft) async throws -> Void
    ) {
        let resolvedUsers = users.isEmpty ? ToDoPreviewData.users : users
        let resolvedUserId = currentUserId ?? resolvedUsers.first?.id ?? 1

        self.mode = mode
        self.users = resolvedUsers
        self.recentLocations = recentLocations.isEmpty ? ToDoPreviewData.recentLocations : recentLocations
        self.onSave = onSave
        _draft = State(
            initialValue: mode.initialDraft(currentUserId: resolvedUserId)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    titleSection
                    detailsSection
                    locationSection
                    summarySection

                    if let saveErrorMessage {
                        ToDoInlineBadge(
                            text: saveErrorMessage,
                            systemImage: "exclamationmark.triangle.fill",
                            tone: .warning
                        )
                    }

                    PrimaryActionButton(
                        title: isSaving ? savingTitle : actionTitle,
                        systemImage: actionSystemImage
                    ) {
                        save()
                    }
                }
                .padding(AppSpacing.screen)
                .padding(.bottom, AppSpacing.xLarge)
            }
            .background(AppColors.pageBackground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || !draft.isValid)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add:
            return "New To Do"
        case .edit:
            return "To Do Details"
        }
    }

    private var actionTitle: String {
        switch mode {
        case .add:
            return "Add To Do"
        case .edit:
            return "Save Changes"
        }
    }

    private var savingTitle: String {
        switch mode {
        case .add:
            return "Adding"
        case .edit:
            return "Saving"
        }
    }

    private var actionSystemImage: String {
        switch mode {
        case .add:
            return "plus"
        case .edit:
            return "checkmark"
        }
    }

    private var titleSection: some View {
        ToDoFormPanel(title: "Task", systemImage: "checklist") {
            ToDoTextFieldRow(
                title: "Title",
                systemImage: "text.cursor",
                text: $draft.name,
                prompt: "What needs doing?"
            )
        }
    }

    private var detailsSection: some View {
        ToDoFormPanel(title: "Details", systemImage: "slider.horizontal.3") {
            VStack(spacing: 0) {
                ToDoCreatedByRow(user: selectedUser)

                Divider()
                    .padding(.leading, 42)
                    .padding(.vertical, AppSpacing.medium)

                ToDoDueDatePicker(
                    dueDateOptions: dueDateOptions,
                    selectedDueDateID: $draft.dueDateID,
                    selectedDate: $draft.date
                )

                Divider()
                    .padding(.leading, 42)
                    .padding(.vertical, AppSpacing.medium)

                ToDoRecurringPicker(selectedRecurring: $draft.recurring)
            }
        }
    }

    private var locationSection: some View {
        ToDoFormPanel(title: "Location", systemImage: "mappin.and.ellipse") {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                ToDoLocationSearchField(
                    text: $draft.location,
                    suggestions: locationSearch.suggestions,
                    isSearching: locationSearch.isSearching,
                    errorMessage: locationSearch.errorMessage
                ) { suggestion in
                    selectLocationSearchSuggestion(suggestion)
                }
                .onAppear {
                    locationSearch.update(query: draft.location)
                }
                .onChange(of: draft.location) { _, newLocation in
                    locationSearch.update(query: newLocation)
                }

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
                                draft.location = location.displayTitle
                                draft.locationIds = [location.id]
                                draft.saveLocation = false
                                locationSearch.select(query: location.displayTitle)
                            } label: {
                                HStack(spacing: AppSpacing.xSmall) {
                                    Image(systemName: location.previewSystemImage)
                                        .font(.caption.weight(.semibold))

                                    Text(location.displayTitle)
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
            ToDoIconBadge(systemImage: "checklist", tone: .accent)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(draft.name.isEmpty ? "New to do" : draft.name)
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
        isNewLocation(draft.location)
    }

    private func isNewLocation(_ locationText: String) -> Bool {
        let normalizedLocation = normalizedLocationName(locationText)

        guard !normalizedLocation.isEmpty else {
            return false
        }

        return !recentLocations.contains { savedLocation in
            isSavedLocationMatch(input: normalizedLocation, saved: normalizedLocationName(savedLocation.displayTitle))
        }
    }

    private var selectedDueDate: ToDoDueDateOption {
        if let option = dueDateOptions.first(where: { $0.id == draft.dueDateID }) {
            return option
        }

        if let date = draft.date {
            return ToDoDueDateOption(
                id: "custom",
                title: Self.shortDateFormatter.string(from: date),
                tone: .accent,
                date: date
            )
        }

        return dueDateOptions[0]
    }

    private var selectedUser: LevyHomeUser {
        users.first { $0.id == draft.createdBy } ?? ToDoPreviewData.users[0]
    }

    private var summaryText: String {
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(selectedDueDate.title) • \(location.isEmpty ? "No location" : location)"
    }

    private func selectLocationSearchSuggestion(_ suggestion: ToDoLocationSearchSuggestion) {
        draft.location = suggestion.displayText
        draft.locationIds = nil
        draft.saveLocation = isNewLocation(suggestion.displayText)
        locationSearch.select(query: suggestion.displayText)
    }

    private func normalizedLocationName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isSavedLocationMatch(input: String, saved: String) -> Bool {
        input == saved || input.hasPrefix("\(saved),")
    }

    private func save() {
        guard draft.isValid, !isSaving else {
            return
        }

        isSaving = true
        saveErrorMessage = nil

        Task {
            do {
                try await onSave(draft)
                dismiss()
            } catch {
                saveErrorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

struct ToDoFormPanel<Content: View>: View {
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

private struct ToDoLocationSearchField: View {
    @Binding var text: String
    let suggestions: [ToDoLocationSearchSuggestion]
    let isSearching: Bool
    let errorMessage: String?
    let onSelectSuggestion: (ToDoLocationSearchSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Place or address")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.mutedText)

                    TextField("Search places or addresses", text: $text)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(AppSpacing.medium)

            if let errorMessage {
                Divider()

                HStack(spacing: AppSpacing.small) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))

                    Text(errorMessage)
                        .font(.caption)
                }
                .foregroundStyle(AppColors.warning)
                .padding(AppSpacing.medium)
            } else if !suggestions.isEmpty {
                Divider()

                VStack(spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            onSelectSuggestion(suggestion)
                        } label: {
                            HStack(alignment: .top, spacing: AppSpacing.medium) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppColors.accent)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                                    Text(suggestion.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(AppColors.mutedText)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer(minLength: AppSpacing.small)

                                Image(systemName: "plus.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppColors.accent)
                            }
                            .padding(AppSpacing.medium)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if suggestion.id != suggestions.last?.id {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .background(AppColors.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ToDoCreatedByRow: View {
    let user: LevyHomeUser

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            Image(systemName: "person.crop.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Created by")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(user.fullName)
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
            }

            Spacer()

            Text(user.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(AppColors.accent)
                .clipShape(Circle())
        }
    }
}

private struct ToDoDueDatePicker: View {
    let dueDateOptions: [ToDoDueDateOption]
    @Binding var selectedDueDateID: String
    @Binding var selectedDate: Date?

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
                        selectedDate = option.date
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

private struct ToDoRecurringPicker: View {
    @Binding var selectedRecurring: ToDoRecurring?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            ToDoFormRowHeader(
                title: "Repeats",
                subtitle: "Leave off for one-time tasks",
                systemImage: "repeat"
            )

            FlowLayout(spacing: AppSpacing.small, rowSpacing: AppSpacing.small) {
                recurringButton(title: "Never", recurring: nil)

                ForEach(ToDoRecurring.allCases) { recurring in
                    recurringButton(title: recurring.displayTitle, recurring: recurring)
                }
            }
        }
    }

    private func recurringButton(title: String, recurring: ToDoRecurring?) -> some View {
        let isSelected = selectedRecurring == recurring

        return Button {
            selectedRecurring = recurring
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, AppSpacing.medium)
                .frame(height: 32)
                .foregroundStyle(isSelected ? Color.white : AppColors.accent)
                .background(isSelected ? AppColors.accent : AppColors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
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

#Preview {
    NavigationStack {
        ToDoView()
    }
}
