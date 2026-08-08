import Combine
import Foundation

typealias ToDoListSnapshotLoader = () async throws -> ToDoListResponse

@MainActor
final class ToDoViewModel: ObservableObject {
    @Published private(set) var items: [ToDoItem] = []
    @Published private(set) var categories: [ToDoCategory] = []
    @Published private(set) var locations: [ToDoLocation] = []
    @Published private(set) var users: [LevyHomeUser] = []
    @Published private(set) var activeViewers: [ToDoListViewerPresence] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var mutatingItemIDs: Set<Int> = []

    private var liveService: ToDoListLiveServicing?
    private var loadLiveSnapshot: ToDoListSnapshotLoader?
    private var liveUpdatesTask: Task<Void, Never>?
    private var currentViewerId: String?
    private var currentViewerUserId: Int?
    private var isSyncingLiveSnapshot = false
    private var committedStateRevision: UInt64 = 0

    deinit {
        liveUpdatesTask?.cancel()
        liveService?.disconnect()
    }

    var sections: [ToDoTaskSection] {
        guard !items.isEmpty else {
            return []
        }

        let tasks = items.map { task(from: $0) }
        let familyTasks = tasks.filter(\.isFamilyItem)
        let personalTasks = tasks.filter { !$0.isFamilyItem }

        return [
            familyTasks.isEmpty ? nil : ToDoTaskSection(
                id: "family",
                title: "Family",
                systemImage: "person.2.fill",
                tone: .accent,
                tasks: familyTasks
            ),
            personalTasks.isEmpty ? nil : ToDoTaskSection(
                id: "me",
                title: "Me",
                systemImage: "person.fill",
                tone: .neutral,
                tasks: personalTasks
            ),
        ].compactMap { $0 }
    }

    func load(apiClient: APIClient, visibleTo userId: Int? = nil, force: Bool = false) async {
        guard !isLoading || force else {
            return
        }

        isLoading = true

        defer {
            isLoading = false
        }

        do {
            for _ in 0..<2 {
                let revisionAtRequestStart = committedStateRevision
                async let todoListResponse = apiClient.fetchToDoList(visibleTo: userId)
                async let usersResponse = apiClient.fetchUsers()
                let (todoList, fetchedUsers) = try await (todoListResponse, usersResponse)

                if applySnapshot(
                    todoList,
                    users: fetchedUsers.users,
                    ifUnchangedSince: revisionAtRequestStart
                ) {
                    errorMessage = nil
                    return
                }
            }

            hasLoaded = true
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }

    func residentAvatarStates(currentViewerId: String?) -> [ResidentAvatarState] {
        var viewingResidentIds = Set(
            activeViewers.compactMap { viewer in
                Self.residentIdentity(for: viewer)?.id
            }
        )

        if let currentViewerId,
           let currentResident = Self.residentIdentity(forViewerId: currentViewerId) {
            viewingResidentIds.insert(currentResident.id)
        }

        return ResidentAvatarState.allResidents(viewingResidentIds: viewingResidentIds)
    }

    func startLiveUpdatesIfNeeded(
        liveService: ToDoListLiveServicing,
        currentViewerId: String,
        loadSnapshot: @escaping ToDoListSnapshotLoader
    ) {
        if self.currentViewerId == currentViewerId, liveUpdatesTask != nil {
            return
        }

        stopLiveUpdates()

        self.liveService = liveService
        loadLiveSnapshot = loadSnapshot
        self.currentViewerId = currentViewerId
        currentViewerUserId = Self.userId(forViewerId: currentViewerId)

        liveUpdatesTask = Task { [weak self] in
            for await message in liveService.messages() {
                guard !Task.isCancelled else {
                    break
                }

                await self?.applyLiveMessage(message)
            }
        }
    }

    func stopLiveUpdates() {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        liveService?.disconnect()
        liveService = nil
        loadLiveSnapshot = nil
        currentViewerId = nil
        currentViewerUserId = nil
        activeViewers = []
    }

    func applyLiveMessage(_ message: ToDoListLiveMessage) async {
        switch message {
        case .hello:
            return
        case .presenceChanged(let viewers, _):
            activeViewers = Self.deduplicatedViewers(viewers)
        case .snapshotRequired:
            await refreshFromLiveSnapshot()
        case .itemCreated(let item, _, _), .itemUpdated(let item, _, _):
            if isVisibleToCurrentViewer(item) {
                apply(item)
            } else {
                removeCommittedItem(id: item.id)
            }
        case .itemDeleted(let itemId, _, _):
            removeCommittedItem(id: itemId)
        case .unknown:
            return
        }
    }

    #if targetEnvironment(simulator)
    func loadSimulatorPreviewData() {
        items = Self.sortedItems(ToDoPreviewData.simulatorToDoItems)
        categories = ToDoPreviewData.simulatorToDoCategories
        locations = ToDoPreviewData.recentLocations
        users = ToDoPreviewData.users
        errorMessage = nil
        hasLoaded = true
        isLoading = false
    }

    func createSimulatorTask(from draft: ToDoDraft) {
        let item = item(from: draft, id: nextSimulatorItemID(), locationIds: simulatorLocationIds(from: draft))
        apply(item)
        errorMessage = nil
        hasLoaded = true
    }

    func updateSimulatorTask(_ task: ToDoTask, from draft: ToDoDraft) {
        let item = item(from: draft, id: task.id, locationIds: simulatorLocationIds(from: draft))
        apply(item)
        errorMessage = nil
    }

    func toggleSimulatorCompletion(_ task: ToDoTask) {
        guard let item = items.first(where: { $0.id == task.id }) else {
            return
        }

        apply(
            ToDoItem(
                id: item.id,
                name: item.name,
                status: task.isCompleted ? .open : .completed,
                locationIds: item.locationIds,
                locationDisplayText: item.locationDisplayText,
                date: item.date,
                recurring: item.recurring,
                notes: item.notes,
                alerts: item.alerts,
                subtasks: item.subtasks,
                createdBy: item.createdBy,
                createdFor: item.createdFor,
                createdDate: item.createdDate
            )
        )
        errorMessage = nil
    }

    func deleteSimulatorTask(_ task: ToDoTask) {
        removeCommittedItem(id: task.id)
        errorMessage = nil
    }
    #endif

    func createTask(from draft: ToDoDraft, apiClient: APIClient, actor: String?) async throws {
        let locationIds = try await resolveLocationIds(from: draft, apiClient: apiClient)
        let request = CreateToDoItemRequest(
            name: draft.trimmedName,
            status: .open,
            locationIds: locationIds,
            date: Self.isoString(from: draft.date),
            recurring: draft.recurring.flatMap { ToDoItemRecurring(rawValue: $0.rawValue) },
            notes: draft.trimmedNotes.isEmpty ? nil : draft.trimmedNotes,
            createdBy: draft.createdBy,
            createdFor: draft.createdFor,
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
            notes: draft.trimmedNotes.isEmpty ? .null : .value(draft.trimmedNotes),
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
            removeCommittedItem(id: response.itemId)
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

    private static func deduplicatedViewers(
        _ viewers: [ToDoListViewerPresence]
    ) -> [ToDoListViewerPresence] {
        var viewersById: [String: ToDoListViewerPresence] = [:]

        for viewer in viewers {
            let viewerId = viewer.viewerId.lowercased()

            if let existingViewer = viewersById[viewerId],
               existingViewer.lastSeenAt >= viewer.lastSeenAt {
                continue
            }

            viewersById[viewerId] = viewer
        }

        return viewersById.values.sorted { first, second in
            first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
        }
    }

    private static func residentIdentity(for viewer: ToDoListViewerPresence) -> ResidentIdentity? {
        if let resident = residentIdentity(forViewerId: viewer.viewerId) {
            return resident
        }

        let trimmedDisplayName = viewer.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let resident = ResidentIdentity(rawValue: trimmedDisplayName) {
            return resident
        }

        return nil
    }

    private static func residentIdentity(forViewerId viewerId: String) -> ResidentIdentity? {
        let normalizedViewerId = viewerId.lowercased()

        if let resident = ResidentIdentity.allCases.first(where: { $0.toDoListViewerId == normalizedViewerId }) {
            return resident
        }

        return nil
    }

    private static func userId(forViewerId viewerId: String) -> Int? {
        ResidentIdentity.allCases.first { $0.toDoListViewerId == viewerId.lowercased() }?.toDoUserId
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

        items = Self.sortedItems(items)
        committedStateRevision &+= 1
    }

    private func isVisibleToCurrentViewer(_ item: ToDoItem) -> Bool {
        guard let currentViewerUserId else {
            return true
        }

        return item.createdFor.contains(currentViewerUserId)
    }

    private func removeCommittedItem(id itemId: Int) {
        guard items.contains(where: { $0.id == itemId }) else {
            return
        }

        items.removeAll { $0.id == itemId }
        committedStateRevision &+= 1
    }

    private func refreshFromLiveSnapshot() async {
        guard !isSyncingLiveSnapshot, let loadLiveSnapshot else {
            return
        }

        isSyncingLiveSnapshot = true
        defer { isSyncingLiveSnapshot = false }

        do {
            for _ in 0..<2 {
                let revisionAtRequestStart = committedStateRevision
                let snapshot = try await loadLiveSnapshot()

                if applySnapshot(snapshot, ifUnchangedSince: revisionAtRequestStart) {
                    errorMessage = nil
                    return
                }
            }
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func applySnapshot(
        _ snapshot: ToDoListResponse,
        users fetchedUsers: [LevyHomeUser]? = nil,
        ifUnchangedSince revisionAtRequestStart: UInt64
    ) -> Bool {
        guard committedStateRevision == revisionAtRequestStart else {
            return false
        }

        let sortedSnapshotItems = Self.sortedItems(snapshot.items)
        let didChangeList = items != sortedSnapshotItems
            || categories != snapshot.categories
            || locations != snapshot.locations

        items = sortedSnapshotItems
        categories = snapshot.categories
        locations = snapshot.locations

        if let fetchedUsers {
            users = fetchedUsers
        }

        if didChangeList {
            committedStateRevision &+= 1
        }

        hasLoaded = true
        return true
    }

    #if targetEnvironment(simulator)
    private func nextSimulatorItemID() -> Int {
        (items.map(\.id).max() ?? 100) + 1
    }

    private func simulatorLocationIds(from draft: ToDoDraft) -> [Int] {
        if let locationIds = draft.locationIds {
            return locationIds
        }

        let locationName = draft.trimmedLocation
        guard !locationName.isEmpty else {
            return []
        }

        if let existingLocation = locations.first(where: { Self.isSameLocation($0.displayTitle, locationName) }) {
            return [existingLocation.id]
        }

        let nextLocationID = (locations.map(\.id).max() ?? 0) + 1
        locations.insert(
            ToDoLocation(
                id: nextLocationID,
                name: locationName,
                address: nil,
                mapkitTitle: locationName,
                mapkitSubtitle: nil,
                latitude: nil,
                longitude: nil,
                createdBy: draft.createdBy,
                createdDate: Self.isoString(from: Date()) ?? "",
                lastUsedDate: nil,
                useCount: 1,
                isActive: true,
                favoritedBy: [draft.createdBy]
            ),
            at: 0
        )

        return [nextLocationID]
    }

    private func item(from draft: ToDoDraft, id: Int, locationIds: [Int]) -> ToDoItem {
        let locationDisplayText = locationIds.isEmpty
            ? "No location"
            : locations
                .filter { locationIds.contains($0.id) }
                .map(\.displayTitle)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: ", ")

        return ToDoItem(
            id: id,
            name: draft.trimmedName,
            status: ToDoItemStatus(rawValue: draft.status.rawValue) ?? .open,
            locationIds: locationIds,
            locationDisplayText: locationDisplayText.isEmpty ? "No location" : locationDisplayText,
            date: Self.isoString(from: draft.date),
            recurring: draft.recurring.flatMap { ToDoItemRecurring(rawValue: $0.rawValue) },
            notes: draft.trimmedNotes.isEmpty ? nil : draft.trimmedNotes,
            alerts: [],
            subtasks: [],
            createdBy: draft.createdBy,
            createdFor: draft.createdFor,
            createdDate: Self.isoString(from: draft.createdDate)
        )
    }
    #endif

    private func task(from item: ToDoItem) -> ToDoTask {
        ToDoTask(
            id: item.id,
            name: item.name,
            locationIds: item.locationIds.isEmpty ? nil : item.locationIds,
            date: Self.date(from: item.date),
            recurring: item.recurring.flatMap { ToDoRecurring(rawValue: $0.rawValue) },
            createdBy: item.createdBy,
            createdFor: item.createdFor,
            createdDate: Self.date(from: item.createdDate) ?? Date(),
            status: ToDoStatus(rawValue: item.status.rawValue) ?? .open,
            locationDisplayText: item.locationDisplayText,
            isLinkedToFamilyCalendar: false,
            notes: item.notes,
            subtasks: item.subtasks
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

    private static func sortedItems(_ items: [ToDoItem]) -> [ToDoItem] {
        items.sorted(by: areItemsInDisplayOrder)
    }

    private static func areItemsInDisplayOrder(_ first: ToDoItem, _ second: ToDoItem) -> Bool {
        let firstDueDate = date(from: first.date)
        let secondDueDate = date(from: second.date)

        switch (firstDueDate, secondDueDate) {
        case (.some(let firstDueDate), .some(let secondDueDate)) where firstDueDate != secondDueDate:
            return firstDueDate < secondDueDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        let firstCreatedDate = date(from: first.createdDate)
        let secondCreatedDate = date(from: second.createdDate)

        switch (firstCreatedDate, secondCreatedDate) {
        case (.some(let firstCreatedDate), .some(let secondCreatedDate)) where firstCreatedDate != secondCreatedDate:
            return firstCreatedDate > secondCreatedDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        let nameOrder = first.name.localizedCaseInsensitiveCompare(second.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }

        return first.id < second.id
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
