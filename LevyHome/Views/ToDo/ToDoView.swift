import EventKit
import MapKit
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

@MainActor
private final class ToDoViewModel: ObservableObject {
    @Published private(set) var items: [ToDoItem] = []
    @Published private(set) var categories: [ToDoCategory] = []
    @Published private(set) var locations: [ToDoLocation] = []
    @Published private(set) var users: [LevyHomeUser] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var mutatingItemIDs: Set<Int> = []

    var sections: [ToDoTaskSection] {
        guard !items.isEmpty else {
            return []
        }

        return [
            ToDoTaskSection(
                id: "todo-list",
                title: "To Do",
                systemImage: "checklist",
                tone: .accent,
                tasks: items.map { task(from: $0) }
            )
        ]
    }

    func load(apiClient: APIClient, force: Bool = false) async {
        guard !isLoading || force else {
            return
        }

        isLoading = true

        defer {
            isLoading = false
        }

        do {
            async let todoListResponse = apiClient.fetchToDoList()
            async let usersResponse = apiClient.fetchUsers()
            let (todoList, fetchedUsers) = try await (todoListResponse, usersResponse)

            items = todoList.items
            categories = todoList.categories
            locations = todoList.locations
            users = fetchedUsers.users
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }

    func createTask(from draft: ToDoDraft, apiClient: APIClient, actor: String?) async throws {
        let locationIds = try await resolveLocationIds(from: draft, apiClient: apiClient)
        let request = CreateToDoItemRequest(
            name: draft.trimmedName,
            status: .open,
            locationIds: locationIds,
            date: Self.isoString(from: draft.date),
            recurring: draft.recurring.flatMap { ToDoItemRecurring(rawValue: $0.rawValue) },
            createdBy: draft.createdBy,
            actor: actor
        )

        let response = try await apiClient.createToDoItem(request)
        apply(response.item)
        errorMessage = nil
    }

    func updateTask(_ task: ToDoTask, from draft: ToDoDraft, apiClient: APIClient, actor: String?) async throws {
        guard !mutatingItemIDs.contains(task.id) else {
            return
        }

        mutatingItemIDs.insert(task.id)

        defer {
            mutatingItemIDs.remove(task.id)
        }

        let locationIds = try await resolveLocationIds(from: draft, apiClient: apiClient)
        let request = UpdateToDoItemRequest(
            name: draft.trimmedName,
            status: ToDoItemStatus(rawValue: draft.status.rawValue),
            locationIds: locationIds,
            date: draft.date.map { .value(Self.isoString(from: $0) ?? "") } ?? .null,
            recurring: draft.recurring
                .flatMap { ToDoItemRecurring(rawValue: $0.rawValue) }
                .map { .value($0) } ?? .null,
            createdBy: .value(draft.createdBy),
            actor: actor
        )
        let response = try await apiClient.updateToDoItem(id: task.id, request)

        apply(response.item)
        errorMessage = nil
    }

    func toggleCompletion(_ task: ToDoTask, apiClient: APIClient, actor: String?) async {
        guard !mutatingItemIDs.contains(task.id) else {
            return
        }

        mutatingItemIDs.insert(task.id)

        defer {
            mutatingItemIDs.remove(task.id)
        }

        do {
            let nextStatus: ToDoItemStatus = task.isCompleted ? .open : .completed
            let response = try await apiClient.updateToDoItem(
                id: task.id,
                UpdateToDoItemRequest(status: nextStatus, actor: actor)
            )

            apply(response.item)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTask(_ task: ToDoTask, apiClient: APIClient, actor: String?) async {
        guard !mutatingItemIDs.contains(task.id) else {
            return
        }

        mutatingItemIDs.insert(task.id)

        defer {
            mutatingItemIDs.remove(task.id)
        }

        do {
            let response = try await apiClient.deleteToDoItem(id: task.id, actor: actor)
            items.removeAll { $0.id == response.itemId }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func userId(for residentName: String) -> Int? {
        let normalizedResidentName = residentName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedResidentName.isEmpty else {
            return users.first?.id
        }

        return users.first { user in
            user.firstName.localizedCaseInsensitiveCompare(normalizedResidentName) == .orderedSame ||
                user.fullName.localizedCaseInsensitiveCompare(normalizedResidentName) == .orderedSame
        }?.id ?? users.first?.id
    }

    private func resolveLocationIds(
        from draft: ToDoDraft,
        apiClient: APIClient
    ) async throws -> [Int] {
        if let locationIds = draft.locationIds,
           !locationIds.isEmpty,
           locationNameMatchesSelectedIds(draft.trimmedLocation, locationIds: locationIds) {
            return locationIds
        }

        let locationName = draft.trimmedLocation

        guard !locationName.isEmpty else {
            return []
        }

        if let existingLocation = locations.first(where: { Self.isSameLocation($0.displayTitle, locationName) }) {
            return [existingLocation.id]
        }

        guard draft.saveLocation else {
            return []
        }

        let response = try await apiClient.createToDoLocation(
            CreateToDoLocationRequest(
                name: locationName,
                address: nil,
                mapkitTitle: locationName,
                mapkitSubtitle: nil,
                latitude: nil,
                longitude: nil,
                createdBy: draft.createdBy,
                favoritedBy: [draft.createdBy]
            )
        )

        locations.insert(response.location, at: 0)

        return [response.location.id]
    }

    private func locationNameMatchesSelectedIds(_ locationName: String, locationIds: [Int]) -> Bool {
        guard !locationName.isEmpty else {
            return true
        }

        let selectedLocations = locations.filter { locationIds.contains($0.id) }
        let singleLocationMatches = selectedLocations.contains { Self.isSameLocation($0.displayTitle, locationName) }
        let combinedLocationText = selectedLocations
            .map(\.displayTitle)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: ", ")

        return singleLocationMatches || Self.isSameLocation(combinedLocationText, locationName)
    }

    private func apply(_ item: ToDoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
    }

    private func task(from item: ToDoItem) -> ToDoTask {
        ToDoTask(
            id: item.id,
            name: item.name,
            locationIds: item.locationIds.isEmpty ? nil : item.locationIds,
            date: Self.date(from: item.date),
            recurring: item.recurring.flatMap { ToDoRecurring(rawValue: $0.rawValue) },
            createdBy: item.createdBy,
            createdDate: Self.date(from: item.createdDate) ?? Date(),
            status: ToDoStatus(rawValue: item.status.rawValue) ?? .open,
            locationDisplayText: item.locationDisplayText,
            isLinkedToFamilyCalendar: false,
            previewNote: nil
        )
    }

    private static func isSameLocation(_ first: String, _ second: String) -> Bool {
        first.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(second.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private static func date(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        return iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value)
    }

    private static func isoString(from date: Date?) -> String? {
        date.map { iso8601WithFractionalSeconds.string(from: $0) }
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
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

private struct ToDoCalendarPanel: View {
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

private struct ToDoCalendarEventDetailSheet: View {
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

private struct ToDoCalendarDetailRow: View {
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

private struct ToDoRemindersPanel: View {
    let state: ToDoPersonalRemindersState
    let reminders: [ToDoReminder]
    let onCompleteReminder: (ToDoReminder) -> Void
    let onSelectReminder: (ToDoReminder) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                ToDoIconBadge(systemImage: "checklist", tone: .accent)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Reminders")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("iOS Reminders")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                }

                Spacer()

                ToDoStatusPill(
                    text: state.statusText(reminderCount: reminders.count),
                    systemImage: state.statusSystemImage(reminderCount: reminders.count),
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
            .frame(width: 48)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Text(reminder.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let priorityText = reminder.priorityBadgeText {
                        ToDoInlineBadge(text: priorityText, systemImage: "exclamationmark", tone: .warning)
                    }
                }

                ToDoReminderMetadataRow(text: reminder.metadataText)
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

private struct ToDoReminderMetadataRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
            Image(systemName: "list.bullet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColors.mutedText)
                .lineLimit(2)
        }
    }
}

private struct ToDoReminderDetailSheet: View {
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

private final class ToDoLocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [ToDoLocationSearchSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var selectedQuery: String?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedQuery.count >= 2 else {
            clearResults()
            completer.queryFragment = ""
            selectedQuery = nil
            return
        }

        if normalizedQuery == selectedQuery {
            clearResults()
            return
        }

        selectedQuery = nil
        errorMessage = nil

        guard completer.queryFragment != normalizedQuery else {
            return
        }

        isSearching = true
        completer.queryFragment = normalizedQuery
    }

    func select(query: String) {
        selectedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        clearResults()
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let nextSuggestions = Self.suggestions(from: completer.results)

        DispatchQueue.main.async {
            self.suggestions = nextSuggestions
            self.isSearching = false
            self.errorMessage = nil
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.suggestions = []
            self.isSearching = false
            self.errorMessage = "Location search unavailable"
        }
    }

    private func clearResults() {
        suggestions = []
        isSearching = false
        errorMessage = nil
    }

    private static func suggestions(from completions: [MKLocalSearchCompletion]) -> [ToDoLocationSearchSuggestion] {
        var seenIDs = Set<String>()

        return completions.compactMap { completion in
            let title = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = completion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty else {
                return nil
            }

            let id = "\(title)|\(subtitle)".lowercased()

            guard !seenIDs.contains(id) else {
                return nil
            }

            seenIDs.insert(id)
            return ToDoLocationSearchSuggestion(id: id, title: title, subtitle: subtitle)
        }
    }
}

private struct ToDoLocationSearchSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String

    var displayText: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}

@MainActor
final class FamilyCalendarService {
    static let shared = FamilyCalendarService()

    private let eventStore: EKEventStore
    private let calendar: Calendar
    private let familyCalendarName = "Family"

    init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    fileprivate func loadTodaysFamilyEvents() async throws -> FamilyCalendarLoadResult {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            guard try await requestFullAccess() else {
                return FamilyCalendarLoadResult(state: .permissionNeeded, events: [])
            }

            return try readTodaysFamilyEvents()
        case .fullAccess:
            return try readTodaysFamilyEvents()
        case .denied:
            return FamilyCalendarLoadResult(state: .permissionNeeded, events: [])
        case .restricted:
            return FamilyCalendarLoadResult(state: .restricted, events: [])
        case .writeOnly:
            return FamilyCalendarLoadResult(state: .permissionNeeded, events: [])
        @unknown default:
            return FamilyCalendarLoadResult(state: .failed("Calendar access returned an unknown status."), events: [])
        }
    }

    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func readTodaysFamilyEvents() throws -> FamilyCalendarLoadResult {
        let familyCalendars = eventStore.calendars(for: .event).filter { calendar in
            calendar.title.trimmingCharacters(in: .whitespacesAndNewlines) == familyCalendarName
        }

        guard !familyCalendars.isEmpty else {
            return FamilyCalendarLoadResult(state: .calendarNotFound, events: [])
        }

        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return FamilyCalendarLoadResult(state: .failed("Unable to calculate today's Family Calendar window."), events: [])
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: familyCalendars
        )
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isDetached }
            .map(ToDoCalendarEvent.init(event:))

        return FamilyCalendarLoadResult(state: .synced, events: events)
    }
}

@MainActor
private final class ToDoFamilyCalendarViewModel: ObservableObject {
    @Published private(set) var state: ToDoFamilyCalendarState = .idle
    @Published private(set) var events: [ToDoCalendarEvent] = []

    private let service: FamilyCalendarService
    private let userDefaults: UserDefaults
    private let completionStorageKey = "familyCalendarCompletedEventIDs"
    private var isLoadingToday = false
    private var completedEventIDs: Set<String>

    init(service: FamilyCalendarService? = nil, userDefaults: UserDefaults = .standard) {
        self.service = service ?? FamilyCalendarService.shared
        self.userDefaults = userDefaults
        completedEventIDs = Set(userDefaults.stringArray(forKey: completionStorageKey) ?? [])
    }

    var eventCount: Int {
        events.count
    }

    var displayEvents: [ToDoCalendarEvent] {
        events.sorted { first, second in
            if first.isCompleted != second.isCompleted {
                return !first.isCompleted && second.isCompleted
            }

            if first.startDate != second.startDate {
                return first.startDate < second.startDate
            }

            return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
        }
    }

    func loadToday(force: Bool = false) async {
        if !force, state == .synced {
            return
        }

        guard !isLoadingToday else {
            return
        }

        isLoadingToday = true
        let previousState = state
        let previousEvents = events
        state = EKEventStore.authorizationStatus(for: .event) == .notDetermined ? .requestingPermission : .loading

        defer {
            isLoadingToday = false
        }

        do {
            let result = try await service.loadTodaysFamilyEvents()
            state = result.state
            events = result.events.map { event in
                event.withCompletion(completedEventIDs.contains(event.completionID))
            }
        } catch {
            guard !error.isTaskCancellation else {
                state = previousState
                events = previousEvents
                return
            }

            state = .failed(error.localizedDescription)
            events = []
        }
    }

    func toggleCompletion(for event: ToDoCalendarEvent) {
        if completedEventIDs.contains(event.completionID) {
            completedEventIDs.remove(event.completionID)
        } else {
            completedEventIDs.insert(event.completionID)
        }

        persistCompletionIDs()
        events = events.map { existingEvent in
            guard existingEvent.completionID == event.completionID else {
                return existingEvent
            }

            return existingEvent.withCompletion(completedEventIDs.contains(event.completionID))
        }
    }

    private func persistCompletionIDs() {
        userDefaults.set(Array(completedEventIDs).sorted(), forKey: completionStorageKey)
    }
}

private struct FamilyCalendarLoadResult {
    let state: ToDoFamilyCalendarState
    let events: [ToDoCalendarEvent]
}

private enum ToDoFamilyCalendarState: Equatable {
    case idle
    case requestingPermission
    case loading
    case synced
    case permissionNeeded
    case restricted
    case calendarNotFound
    case failed(String)

    func statusText(eventCount: Int) -> String {
        switch self {
        case .idle, .requestingPermission, .loading:
            return "Syncing"
        case .synced:
            return eventCount == 1 ? "1 event today" : "\(eventCount) events today"
        case .permissionNeeded:
            return "Permission Needed"
        case .restricted:
            return "Restricted"
        case .calendarNotFound:
            return "Missing"
        case .failed:
            return "Error"
        }
    }

    func statusSystemImage(eventCount: Int) -> String {
        switch self {
        case .idle, .requestingPermission, .loading:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "calendar"
        case .permissionNeeded, .restricted:
            return "lock.circle"
        case .calendarNotFound:
            return "calendar.badge.exclamationmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var statusTone: ToDoTone {
        switch self {
        case .idle, .requestingPermission, .loading:
            return .accent
        case .synced:
            return .success
        case .permissionNeeded, .restricted, .calendarNotFound:
            return .warning
        case .failed:
            return .critical
        }
    }
}

@MainActor
private final class PersonalRemindersService {
    static let shared = PersonalRemindersService()

    private let eventStore: EKEventStore
    private let calendar: Calendar

    init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    fileprivate func loadIncompleteReminders() async throws -> PersonalRemindersLoadResult {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            guard try await requestFullAccess() else {
                return PersonalRemindersLoadResult(state: .permissionNeeded, reminders: [])
            }

            return try await readIncompleteReminders()
        case .fullAccess:
            return try await readIncompleteReminders()
        case .denied:
            return PersonalRemindersLoadResult(state: .permissionNeeded, reminders: [])
        case .restricted:
            return PersonalRemindersLoadResult(state: .restricted, reminders: [])
        case .writeOnly:
            return PersonalRemindersLoadResult(state: .permissionNeeded, reminders: [])
        @unknown default:
            return PersonalRemindersLoadResult(state: .failed("Reminders access returned an unknown status."), reminders: [])
        }
    }

    fileprivate func completeReminder(_ reminder: ToDoReminder) async throws {
        guard let ekReminder = eventStore.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder else {
            throw PersonalRemindersServiceError.reminderNotFound
        }

        ekReminder.isCompleted = true
        try eventStore.save(ekReminder, commit: true)
    }

    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func readIncompleteReminders() async throws -> PersonalRemindersLoadResult {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        let reminders = await fetchReminders(matching: predicate)
            .filter { !$0.isCompleted }
            .map { ToDoReminder(reminder: $0, calendar: calendar) }

        return PersonalRemindersLoadResult(state: .synced, reminders: reminders)
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
}

private enum PersonalRemindersServiceError: LocalizedError {
    case reminderNotFound

    var errorDescription: String? {
        switch self {
        case .reminderNotFound:
            return "The reminder could not be found."
        }
    }
}

@MainActor
private final class ToDoPersonalRemindersViewModel: ObservableObject {
    @Published private(set) var state: ToDoPersonalRemindersState = .idle
    @Published private(set) var reminders: [ToDoReminder] = []

    private let service: PersonalRemindersService
    private var isLoadingReminders = false
    private var completingReminderIDs = Set<String>()

    init(service: PersonalRemindersService? = nil) {
        self.service = service ?? PersonalRemindersService.shared
    }

    var reminderCount: Int {
        reminders.count
    }

    var displayReminders: [ToDoReminder] {
        reminders.sorted { first, second in
            if first.sortDate != second.sortDate {
                return first.sortDate < second.sortDate
            }

            if first.listTitle.localizedCaseInsensitiveCompare(second.listTitle) != .orderedSame {
                return first.listTitle.localizedCaseInsensitiveCompare(second.listTitle) == .orderedAscending
            }

            return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
        }
    }

    func loadReminders(force: Bool = false) async {
        if !force, state == .synced {
            return
        }

        guard !isLoadingReminders else {
            return
        }

        isLoadingReminders = true
        let previousState = state
        let previousReminders = reminders
        state = EKEventStore.authorizationStatus(for: .reminder) == .notDetermined ? .requestingPermission : .loading

        defer {
            isLoadingReminders = false
        }

        do {
            let result = try await service.loadIncompleteReminders()
            state = result.state
            reminders = result.reminders
        } catch {
            guard !error.isTaskCancellation else {
                state = previousState
                reminders = previousReminders
                return
            }

            state = .failed(error.localizedDescription)
            reminders = []
        }
    }

    func complete(_ reminder: ToDoReminder) async {
        guard !completingReminderIDs.contains(reminder.id) else {
            return
        }

        completingReminderIDs.insert(reminder.id)

        defer {
            completingReminderIDs.remove(reminder.id)
        }

        do {
            try await service.completeReminder(reminder)
            reminders.removeAll { $0.id == reminder.id }
            state = .synced
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            state = .failed(error.localizedDescription)
        }
    }
}

private struct PersonalRemindersLoadResult {
    let state: ToDoPersonalRemindersState
    let reminders: [ToDoReminder]
}

private enum ToDoPersonalRemindersState: Equatable {
    case idle
    case requestingPermission
    case loading
    case synced
    case permissionNeeded
    case restricted
    case failed(String)

    func statusText(reminderCount: Int) -> String {
        switch self {
        case .idle, .requestingPermission, .loading:
            return "Syncing"
        case .synced:
            return reminderCount == 1 ? "1 reminder" : "\(reminderCount) reminders"
        case .permissionNeeded:
            return "Permission Needed"
        case .restricted:
            return "Restricted"
        case .failed:
            return "Error"
        }
    }

    func statusSystemImage(reminderCount: Int) -> String {
        switch self {
        case .idle, .requestingPermission, .loading:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checklist"
        case .permissionNeeded, .restricted:
            return "lock.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var statusTone: ToDoTone {
        switch self {
        case .idle, .requestingPermission, .loading:
            return .accent
        case .synced:
            return .success
        case .permissionNeeded, .restricted:
            return .warning
        case .failed:
            return .critical
        }
    }
}

private struct ToDoReminder: Identifiable {
    let id: String
    let calendarItemIdentifier: String
    let title: String
    let listTitle: String
    let dueDate: Date?
    let hasDueTime: Bool
    let notes: String?
    let url: URL?
    let priority: Int

    init(reminder: EKReminder, calendar: Calendar = .current) {
        let identifier = reminder.calendarItemIdentifier
        let dueDateComponents = reminder.dueDateComponents

        id = identifier
        calendarItemIdentifier = identifier
        title = Self.normalizedOptionalText(reminder.title) ?? "Untitled reminder"
        listTitle = reminder.calendar?.title ?? "Reminders"
        dueDate = Self.date(from: dueDateComponents, fallbackCalendar: calendar)
        hasDueTime = Self.hasTime(in: dueDateComponents)
        notes = Self.normalizedOptionalText(reminder.notes)
        url = reminder.url
        priority = reminder.priority
    }

    var sortDate: Date {
        dueDate ?? .distantFuture
    }

    var dueBadgeTitle: String {
        guard let dueDate else {
            return "No"
        }

        if hasDueTime {
            return Self.timeFormatter.string(from: dueDate)
        }

        if Calendar.current.isDateInToday(dueDate) {
            return "Today"
        }

        if Calendar.current.isDateInTomorrow(dueDate) {
            return "Tmrw"
        }

        if dueDate < Calendar.current.startOfDay(for: Date()) {
            return Self.monthFormatter.string(from: dueDate)
        }

        return Self.monthFormatter.string(from: dueDate)
    }

    var dueBadgeSubtitle: String {
        guard let dueDate else {
            return "Date"
        }

        if hasDueTime {
            return Self.periodFormatter.string(from: dueDate)
        }

        if Calendar.current.isDateInToday(dueDate) || Calendar.current.isDateInTomorrow(dueDate) {
            return "Due"
        }

        return Self.dayFormatter.string(from: dueDate)
    }

    var dueDetailText: String {
        guard let dueDate else {
            return "No due date"
        }

        let dateText: String
        if Calendar.current.isDateInToday(dueDate) {
            dateText = "today"
        } else if Calendar.current.isDateInTomorrow(dueDate) {
            dateText = "tomorrow"
        } else {
            dateText = Self.detailDateFormatter.string(from: dueDate)
        }

        if hasDueTime {
            return "Due \(dateText) at \(Self.detailTimeFormatter.string(from: dueDate))"
        }

        return "Due \(dateText)"
    }

    var metadataText: String {
        "\(listTitle) - \(dueDetailText)"
    }

    var priorityText: String {
        switch priority {
        case 1...4:
            return "High"
        case 5:
            return "Medium"
        case 6...9:
            return "Low"
        default:
            return "No priority"
        }
    }

    var priorityBadgeText: String? {
        priorityText == "High" ? "High" : nil
    }

    var dueTone: ToDoTone {
        guard let dueDate else {
            return .neutral
        }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        if dueDate < startOfToday || Calendar.current.isDateInToday(dueDate) {
            return .warning
        }

        return .accent
    }

    private static func date(from components: DateComponents?, fallbackCalendar: Calendar) -> Date? {
        guard let components else {
            return nil
        }

        let calendar = components.calendar ?? fallbackCalendar
        return calendar.date(from: components)
    }

    private static func hasTime(in components: DateComponents?) -> Bool {
        guard let components else {
            return false
        }

        return components.hour != nil || components.minute != nil || components.second != nil
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let detailTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ToDoCalendarEvent: Identifiable {
    let id: String
    let completionID: String
    let title: String
    let calendarTitle: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: URL?
    let isCompleted: Bool

    init(
        id: String,
        completionID: String,
        title: String,
        calendarTitle: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        url: URL?,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.completionID = completionID
        self.title = title
        self.calendarTitle = calendarTitle
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = Self.normalizedOptionalText(location)
        self.notes = Self.normalizedOptionalText(notes)
        self.url = url
        self.isCompleted = isCompleted
    }

    init(event: EKEvent) {
        let eventIdentifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let startTimestamp = Int(event.startDate.timeIntervalSince1970)
        let completionID = "\(eventIdentifier)-\(startTimestamp)"

        self.init(
            id: completionID,
            completionID: completionID,
            title: Self.normalizedOptionalText(event.title) ?? "Untitled event",
            calendarTitle: event.calendar?.title ?? "Family",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url
        )
    }

    var time: String {
        guard !isAllDay else {
            return "All"
        }

        return Self.timeFormatter.string(from: startDate)
    }

    var period: String {
        guard !isAllDay else {
            return "Day"
        }

        return Self.periodFormatter.string(from: startDate)
    }

    var timeRangeText: String {
        if isAllDay {
            return "All day, \(Self.detailDateFormatter.string(from: startDate))"
        }

        return "\(Self.detailDateFormatter.string(from: startDate)), \(Self.detailTimeFormatter.string(from: startDate)) - \(Self.detailTimeFormatter.string(from: endDate))"
    }

    var locationDisplayText: String {
        location ?? "No location"
    }

    func withCompletion(_ isCompleted: Bool) -> ToDoCalendarEvent {
        ToDoCalendarEvent(
            id: id,
            completionID: completionID,
            title: title,
            calendarTitle: calendarTitle,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            url: url,
            isCompleted: isCompleted
        )
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    private static let detailTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ToDoTaskSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tone: ToDoTone
    let tasks: [ToDoTask]
}

private struct ToDoTask: Identifiable {
    let id: Int
    let name: String
    let locationIds: [Int]?
    let date: Date?
    let recurring: ToDoRecurring?
    let createdBy: Int?
    let createdDate: Date
    let status: ToDoStatus
    let locationDisplayText: String
    let isLinkedToFamilyCalendar: Bool
    let previewNote: String?

    var isCompleted: Bool {
        status == .completed
    }

    var dateDisplayText: String {
        if let date {
            if Calendar.current.isDateInToday(date) {
                return "Today"
            }

            if Calendar.current.isDateInTomorrow(date) {
                return "Tomorrow"
            }

            return Self.shortDateFormatter.string(from: date)
        }

        return recurring?.displayTitle ?? "No date"
    }

    var dateTone: ToDoTone {
        if status == .completed {
            return .success
        }

        guard let date else {
            return recurring == nil ? .neutral : .accent
        }

        if Calendar.current.isDateInToday(date) || date < Date() {
            return .warning
        }

        return .accent
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private enum ToDoEditorMode: Identifiable {
    case add
    case edit(ToDoTask)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let task):
            return "edit-\(task.id)"
        }
    }

    func initialDraft(currentUserId: Int) -> ToDoDraft {
        switch self {
        case .add:
            return ToDoDraft(createdBy: currentUserId)
        case .edit(let task):
            return ToDoDraft(task: task, fallbackCreatedBy: currentUserId)
        }
    }
}

private struct ToDoDraft {
    var name = ""
    var locationIds: [Int]?
    var date: Date? = ToDoPreviewData.today
    var recurring: ToDoRecurring?
    var createdBy: Int
    var createdDate = Date()
    var status: ToDoStatus = .open
    var dueDateID = "today"
    var location = ""
    var saveLocation = true

    init(createdBy: Int = 1) {
        self.createdBy = createdBy
    }

    init(task: ToDoTask, fallbackCreatedBy: Int) {
        name = task.name
        locationIds = task.locationIds
        date = task.date
        recurring = task.recurring
        createdBy = task.createdBy ?? fallbackCreatedBy
        createdDate = task.createdDate
        status = task.status
        dueDateID = Self.dueDateID(for: task.date)
        location = task.locationDisplayText == "No location" ? "" : task.locationDisplayText
        saveLocation = false
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLocation: String {
        location.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty
    }

    private static func dueDateID(for date: Date?) -> String {
        guard let date else {
            return "none"
        }

        if Calendar.current.isDateInToday(date) {
            return "today"
        }

        if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow"
        }

        if let thisWeek = ToDoPreviewData.thisWeek, Calendar.current.isDate(date, inSameDayAs: thisWeek) {
            return "this-week"
        }

        return "custom"
    }
}

private struct ToDoDueDateOption: Identifiable {
    let id: String
    let title: String
    let tone: ToDoTone
    let date: Date?
}

private enum ToDoStatus: String, CaseIterable, Identifiable {
    case open
    case completed
    case canceled

    var id: String { rawValue }
}

private enum ToDoRecurring: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .quarterly:
            return "Quarterly"
        }
    }
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

private extension ToDoLocation {
    var displayTitle: String {
        mapkitTitle ?? name
    }

    var previewSystemImage: String {
        let normalizedName = name.lowercased()

        if normalizedName.contains("home") {
            return "house"
        }

        if normalizedName.contains("pediatric") || normalizedName.contains("doctor") {
            return "cross.case"
        }

        if normalizedName.contains("vet") {
            return "pawprint"
        }

        if normalizedName.contains("county") || normalizedName.contains("office") {
            return "building.columns"
        }

        return "mappin.and.ellipse"
    }
}

private enum ToDoPreviewData {
    static let today = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    static let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
    static let thisWeek = Calendar.current.date(byAdding: .day, value: 4, to: today)
    static let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: today)

    static let users = [
        LevyHomeUser(
            id: 1,
            firstName: "Josh",
            lastName: "Levy",
            email: "josh@example.com",
            mobileDevice: nil,
            lastLogin: nil
        ),
        LevyHomeUser(
            id: 2,
            firstName: "Mallory",
            lastName: "Levy",
            email: "mallory@example.com",
            mobileDevice: nil,
            lastLogin: nil
        )
    ]

    static let dueDateOptions = [
        ToDoDueDateOption(id: "today", title: "Today", tone: .warning, date: today),
        ToDoDueDateOption(id: "tomorrow", title: "Tomorrow", tone: .accent, date: tomorrow),
        ToDoDueDateOption(id: "this-week", title: "This week", tone: .accent, date: thisWeek),
        ToDoDueDateOption(id: "none", title: "No date", tone: .neutral, date: nil)
    ]

    static let recentLocations = [
        ToDoLocation(
            id: 1,
            name: "Home",
            address: nil,
            mapkitTitle: "Home",
            mapkitSubtitle: nil,
            latitude: nil,
            longitude: nil,
            createdBy: 1,
            createdDate: "2026-06-28T15:30:00.000Z",
            lastUsedDate: "2026-06-29T12:00:00.000Z",
            useCount: 8,
            isActive: true,
            favoritedBy: [1, 2]
        ),
        ToDoLocation(
            id: 2,
            name: "Denver Pediatrics",
            address: "123 Wellness Way, Denver, CO",
            mapkitTitle: "Denver Pediatrics",
            mapkitSubtitle: "123 Wellness Way",
            latitude: 39.7392,
            longitude: -104.9903,
            createdBy: 1,
            createdDate: "2026-06-28T15:30:00.000Z",
            lastUsedDate: "2026-06-29T12:00:00.000Z",
            useCount: 3,
            isActive: true,
            favoritedBy: [1, 2]
        ),
        ToDoLocation(
            id: 3,
            name: "Maple Vet Clinic",
            address: "456 Maple St, Denver, CO",
            mapkitTitle: "Maple Vet Clinic",
            mapkitSubtitle: "456 Maple St",
            latitude: 39.75,
            longitude: -104.98,
            createdBy: 2,
            createdDate: "2026-06-28T15:30:00.000Z",
            lastUsedDate: nil,
            useCount: 1,
            isActive: true,
            favoritedBy: [2]
        ),
        ToDoLocation(
            id: 4,
            name: "County office",
            address: nil,
            mapkitTitle: "County office",
            mapkitSubtitle: nil,
            latitude: nil,
            longitude: nil,
            createdBy: 1,
            createdDate: "2026-06-28T15:30:00.000Z",
            lastUsedDate: nil,
            useCount: 1,
            isActive: true,
            favoritedBy: []
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
                    id: 1,
                    name: "Schedule dentist",
                    locationIds: nil,
                    date: today,
                    recurring: nil,
                    createdBy: 1,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "Cherry Creek Dental",
                    isLinkedToFamilyCalendar: false,
                    previewNote: "Find a morning opening next week."
                ),
                ToDoTask(
                    id: 2,
                    name: "Confirm pediatrician paperwork",
                    locationIds: [2],
                    date: today,
                    recurring: nil,
                    createdBy: 2,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "Denver Pediatrics",
                    isLinkedToFamilyCalendar: true,
                    previewNote: "Bring insurance card and forms."
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
                    id: 3,
                    name: "Fix gate latch",
                    locationIds: [1],
                    date: thisWeek,
                    recurring: nil,
                    createdBy: 1,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "Home",
                    isLinkedToFamilyCalendar: false,
                    previewNote: "Measure latch before hardware store run."
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
                    id: 4,
                    name: "Book summer camp",
                    locationIds: nil,
                    date: thisWeek,
                    recurring: nil,
                    createdBy: 2,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "Rec center",
                    isLinkedToFamilyCalendar: false,
                    previewNote: "Check weekly availability."
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
                    id: 5,
                    name: "Renew passport",
                    locationIds: [4],
                    date: nextMonth,
                    recurring: .quarterly,
                    createdBy: 1,
                    createdDate: today,
                    status: .open,
                    locationDisplayText: "County office",
                    isLinkedToFamilyCalendar: false,
                    previewNote: "Make appointment and print forms."
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
