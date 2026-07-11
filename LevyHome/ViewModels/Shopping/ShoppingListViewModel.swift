import Combine
import Foundation

extension ResidentIdentity {
    var shoppingListViewerId: String {
        switch self {
        case .josh:
            return "josh"
        case .mallory:
            return "mallory"
        }
    }
}

struct ShoppingLiveStatusBadge: Equatable {
    let label: String
    let systemImage: String
    let tone: StatusBadgeTone
}

@MainActor
final class ShoppingListViewModel: ObservableObject {
    typealias ShoppingListLoader = () async throws -> ShoppingListResponse
    typealias ShoppingListLookup = (String) async throws -> ShoppingListItemLookupResponse
    typealias ShoppingListCreator = (CreateShoppingListItemRequest) async throws -> ShoppingListMutationResponse
    typealias ShoppingListUpdater = (Int, UpdateShoppingListItemRequest) async throws -> ShoppingListMutationResponse
    typealias ShoppingListDeleter = (Int, String, String?) async throws -> DeleteShoppingListItemResponse
    typealias KrogerProductSearch = (String) async throws -> KrogerProductSearchResponse
    typealias ShoppingTripStarter = (StartShoppingTripRequest) async throws -> ShoppingTripMutationResponse
    typealias ShoppingTripEnder = (EndShoppingTripRequest) async throws -> ShoppingTripMutationResponse
    typealias ShoppingTripDisplayClaimer = (String, ClaimShoppingTripDisplayRequest) async throws -> ClaimShoppingTripDisplayResponse

    @Published private(set) var items: [ShoppingListItem] = []
    @Published private(set) var stores: [ShoppingStore] = []
    @Published private(set) var categories: [ShoppingCategory] = []
    @Published private(set) var activeViewers: [ShoppingListViewerPresence] = []
    @Published private(set) var generatedAt: String?
    @Published private(set) var activeTrip: ShoppingTrip?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCreatingItem = false
    @Published private(set) var isStartingTrip = false
    @Published private(set) var isEndingTrip = false
    @Published private(set) var mutatingItemIDs: Set<Int> = []
    @Published private(set) var liveConnectionState: ShoppingListLiveConnectionState = .idle

    private let loadShoppingList: ShoppingListLoader
    private let lookupShoppingListItem: ShoppingListLookup
    private let createShoppingListItem: ShoppingListCreator
    private let updateShoppingListItem: ShoppingListUpdater
    private let deleteShoppingListItem: ShoppingListDeleter
    private let startShoppingTrip: ShoppingTripStarter
    private let endShoppingTrip: ShoppingTripEnder
    private let claimShoppingTripDisplay: ShoppingTripDisplayClaimer
    private let searchKrogerProducts: KrogerProductSearch?
    private let liveService: ShoppingListLiveServicing?
    private let appLogStore: AppLogStore?
    private let currentViewerId: String?
    private let currentActorName: String?
    private var hasLoaded = false
    private var isSyncingLiveSnapshot = false
    private var liveUpdatesTask: Task<Void, Never>?
    private var liveConnectionStateTask: Task<Void, Never>?

    var isEmpty: Bool {
        hasLoaded && items.isEmpty && errorMessage == nil && !isLoading
    }

    var otherActiveViewers: [ShoppingListViewerPresence] {
        activeViewers.filter { viewer in
            guard let currentViewerId else {
                return true
            }

            return viewer.viewerId.localizedCaseInsensitiveCompare(currentViewerId) != .orderedSame
        }
    }

    var otherActiveViewerLabel: String? {
        let names = otherActiveViewers
            .map { Self.displayName(for: $0) }
            .reduce(into: [String]()) { uniqueNames, name in
                guard !uniqueNames.contains(name) else {
                    return
                }

                uniqueNames.append(name)
            }

        guard !names.isEmpty else {
            return nil
        }

        if names.count == 1 {
            return "\(names[0]) viewing"
        }

        return "\(names.count) viewing"
    }

    var activeViewerInitials: [String] {
        residentAvatarStates.map(\.initial)
    }

    var residentAvatarStates: [ResidentAvatarState] {
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

    var liveStatusBadge: ShoppingLiveStatusBadge? {
        guard liveService != nil else {
            return nil
        }

        switch liveConnectionState {
        case .idle, .connecting:
            return ShoppingLiveStatusBadge(
                label: "Connecting",
                systemImage: "antenna.radiowaves.left.and.right",
                tone: .accent
            )
        case .connected:
            return ShoppingLiveStatusBadge(
                label: "Live",
                systemImage: "dot.radiowaves.left.and.right",
                tone: .success
            )
        case .reconnecting:
            return ShoppingLiveStatusBadge(
                label: "Reconnecting",
                systemImage: "arrow.clockwise",
                tone: .warning
            )
        case .paused:
            return ShoppingLiveStatusBadge(
                label: "Live updates paused",
                systemImage: "wifi.slash",
                tone: .warning
            )
        case .disconnected:
            return ShoppingLiveStatusBadge(
                label: "Live off",
                systemImage: "wifi.slash",
                tone: .neutral
            )
        }
    }

    var defaultShoppingCategoryId: Int? {
        miscellaneousCategory?.id ?? categories.first?.id
    }

    var miscellaneousCategory: ShoppingCategory? {
        categories.first { category in
            category.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare("Miscellaneous") == .orderedSame
        }
    }

    convenience init(
        apiClient: APIClient,
        liveService: ShoppingListLiveServicing? = nil,
        appLogStore: AppLogStore? = nil,
        currentViewerId: String? = nil,
        currentActorName: String? = nil
    ) {
        self.init(
            liveService: liveService,
            appLogStore: appLogStore,
            currentViewerId: currentViewerId,
            currentActorName: currentActorName,
            loadShoppingList: {
                try await apiClient.fetchShoppingList()
            },
            lookupShoppingListItem: { name in
                try await apiClient.lookupShoppingListItem(named: name)
            },
            searchKrogerProducts: { name in
                try await apiClient.searchKrogerProducts(named: name)
            },
            createShoppingListItem: { request in
                try await apiClient.createShoppingListItem(request)
            },
            updateShoppingListItem: { itemId, request in
                try await apiClient.updateShoppingListItem(id: itemId, request)
            },
            deleteShoppingListItem: { itemId, mutationId, actor in
                try await apiClient.deleteShoppingListItem(
                    id: itemId,
                    actor: actor,
                    mutationId: mutationId
                )
            },
            startShoppingTrip: { request in
                try await apiClient.startShoppingTrip(request)
            },
            endShoppingTrip: { request in
                try await apiClient.endShoppingTrip(request)
            },
            claimShoppingTripDisplay: { tripId, request in
                try await apiClient.claimShoppingTripDisplay(tripId: tripId, request: request)
            }
        )
    }

    convenience init(
        liveService: ShoppingListLiveServicing? = nil,
        appLogStore: AppLogStore? = nil,
        currentViewerId: String? = nil,
        currentActorName: String? = nil,
        loadShoppingList: @escaping ShoppingListLoader
    ) {
        self.init(
            liveService: liveService,
            appLogStore: appLogStore,
            currentViewerId: currentViewerId,
            currentActorName: currentActorName,
            loadShoppingList: loadShoppingList,
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            searchKrogerProducts: nil,
            createShoppingListItem: { _ in
                throw APIError.transport("Shopping list creation is not configured.")
            },
            updateShoppingListItem: { _, _ in
                throw APIError.transport("Shopping list updates are not configured.")
            },
            deleteShoppingListItem: { _, _, _ in
                throw APIError.transport("Shopping list deletion is not configured.")
            },
            startShoppingTrip: { _ in
                throw APIError.transport("Shopping trip start is not configured.")
            },
            endShoppingTrip: { _ in
                throw APIError.transport("Shopping trip end is not configured.")
            },
            claimShoppingTripDisplay: { _, _ in
                throw APIError.transport("Shopping trip display recovery is not configured.")
            }
        )
    }

    init(
        liveService: ShoppingListLiveServicing? = nil,
        appLogStore: AppLogStore? = nil,
        currentViewerId: String? = nil,
        currentActorName: String? = nil,
        loadShoppingList: @escaping ShoppingListLoader,
        lookupShoppingListItem: @escaping ShoppingListLookup,
        searchKrogerProducts: KrogerProductSearch? = nil,
        createShoppingListItem: @escaping ShoppingListCreator,
        updateShoppingListItem: @escaping ShoppingListUpdater,
        deleteShoppingListItem: @escaping ShoppingListDeleter,
        startShoppingTrip: @escaping ShoppingTripStarter = { _ in
            throw APIError.transport("Shopping trip start is not configured.")
        },
        endShoppingTrip: @escaping ShoppingTripEnder = { _ in
            throw APIError.transport("Shopping trip end is not configured.")
        },
        claimShoppingTripDisplay: @escaping ShoppingTripDisplayClaimer = { _, _ in
            throw APIError.transport("Shopping trip display recovery is not configured.")
        }
    ) {
        self.loadShoppingList = loadShoppingList
        self.lookupShoppingListItem = lookupShoppingListItem
        self.createShoppingListItem = createShoppingListItem
        self.updateShoppingListItem = updateShoppingListItem
        self.deleteShoppingListItem = deleteShoppingListItem
        self.startShoppingTrip = startShoppingTrip
        self.endShoppingTrip = endShoppingTrip
        self.claimShoppingTripDisplay = claimShoppingTripDisplay
        self.searchKrogerProducts = searchKrogerProducts
        self.liveService = liveService
        self.appLogStore = appLogStore
        self.currentViewerId = currentViewerId

        let trimmedActorName = currentActorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentActorName = trimmedActorName?.isEmpty == false ? trimmedActorName : nil
    }

    deinit {
        liveUpdatesTask?.cancel()
        liveConnectionStateTask?.cancel()
        liveService?.disconnect()
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            startLiveUpdatesIfNeeded()
            return
        }

        let didLoad = await load(isRefresh: false)

        if didLoad {
            startLiveUpdatesIfNeeded()
        }
    }

    func refresh() async {
        let didLoad = await load(isRefresh: true)

        if didLoad {
            startLiveUpdatesIfNeeded()
        }
    }

    func searchProducts(named name: String) async throws -> [KrogerProduct] {
        guard let searchKrogerProducts else {
            throw APIError.transport("Product search is not configured.")
        }

        return try await searchKrogerProducts(name).products
    }

    @discardableResult
    func startTrip(originatingPushDeviceId: String?) async -> ShoppingTripMutationResponse? {
        guard !isStartingTrip else { return nil }
        guard items.contains(where: { !$0.purchased }) else {
            errorMessage = "Add at least one needed item before starting a shopping trip."
            return nil
        }
        guard let actor = currentActorName else {
            errorMessage = "Choose Josh or Mallory before starting a shopping trip."
            return nil
        }
        guard let originatingPushDeviceId, !originatingPushDeviceId.isEmpty else {
            errorMessage = "This iPhone is still registering for notifications. Try starting the trip again in a moment."
            return nil
        }

        isStartingTrip = true
        defer { isStartingTrip = false }

        do {
            let response = try await startShoppingTrip(
                StartShoppingTripRequest(actor: actor, originatingPushDeviceId: originatingPushDeviceId)
            )
            activeTrip = response.activeTrip ?? response.trip
            errorMessage = nil
            return response
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func endTrip() async -> ShoppingTripMutationResponse? {
        guard !isEndingTrip, let activeTrip, let actor = currentActorName else { return nil }
        isEndingTrip = true
        defer { isEndingTrip = false }

        do {
            let response = try await endShoppingTrip(
                EndShoppingTripRequest(tripId: activeTrip.id, actor: actor)
            )
            self.activeTrip = response.activeTrip
            errorMessage = nil
            return response
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func claimActiveTripDisplay(pushDeviceId: String?) async -> ShoppingTripDisplayDisposition? {
        guard let activeTrip, let actor = currentActorName, let pushDeviceId, !pushDeviceId.isEmpty else {
            return nil
        }

        do {
            return try await claimShoppingTripDisplay(
                activeTrip.id,
                ClaimShoppingTripDisplayRequest(actor: actor, pushDeviceId: pushDeviceId)
            ).displayDisposition
        } catch {
            // The shared trip remains usable even when a display claim cannot be recovered.
            return nil
        }
    }

    func startLiveUpdatesIfNeeded() {
        guard liveUpdatesTask == nil, let liveService else {
            return
        }

        liveConnectionStateTask = Task { [weak self] in
            for await state in liveService.connectionStates() {
                guard !Task.isCancelled else {
                    break
                }

                self?.applyLiveConnectionState(state)
            }
        }

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
        liveConnectionStateTask?.cancel()
        liveConnectionStateTask = nil
        liveService?.disconnect()
    }

    func applyLiveConnectionState(_ state: ShoppingListLiveConnectionState) {
        liveConnectionState = state
    }

    func applyLiveMessage(_ message: ShoppingListLiveMessage) async {
        switch message {
        case .hello:
            return
        case .presenceChanged(let viewers, _):
            activeViewers = Self.deduplicatedViewers(viewers)
        case .snapshotRequired:
            activeViewers = []
            await refreshFromLiveSnapshot()
        case .itemCreated(let item, _, _), .itemUpdated(let item, _, _):
            applyCommittedItem(item)
        case .itemDeleted(let itemId, _, _):
            items.removeAll { $0.id == itemId }
        case .storesChanged(let stores, _, _):
            self.stores = stores
        case .categoriesChanged(let categories, _, _):
            self.categories = categories
        case .tripStarted(let trip, _, _), .tripUpdated(let trip, _, _):
            activeTrip = trip
        case .tripEnded:
            activeTrip = nil
        case .unknown:
            return
        }
    }

    func lookupDuplicate(named name: String) async throws -> ShoppingListItem? {
        try await lookupShoppingListItem(name).match
    }

    func isMutatingItem(_ itemId: Int) -> Bool {
        mutatingItemIDs.contains(itemId)
    }

    func createItem(from draft: ShoppingItemDraft) async throws {
        guard !isCreatingItem else {
            return
        }

        isCreatingItem = true

        defer {
            isCreatingItem = false
        }

        let request = draft.createRequest(actor: currentActorName)
        recordShoppingMutationLog(
            level: .info,
            title: "Adding shopping item",
            detail: [
                "name=\(Self.logValue(request.name))",
                "mutationId=\(Self.shortIdentifier(request.mutationId))"
            ].joined(separator: " ")
        )

        do {
            let response = try await createShoppingListItem(request)
            applyCommittedItem(response.item)
            generatedAt = response.generatedAt
            errorMessage = nil
            recordShoppingMutationLog(
                level: .success,
                title: "Shopping item saved",
                detail: [
                    "itemId=\(response.item.id)",
                    "name=\(Self.logValue(response.item.name))",
                    "mutationId=\(Self.shortIdentifier(response.mutationId))"
                ].joined(separator: " ")
            )
        } catch {
            errorMessage = error.localizedDescription
            recordShoppingMutationLog(
                level: .error,
                title: "Shopping item save failed",
                detail: [
                    "name=\(Self.logValue(request.name))",
                    "mutationId=\(Self.shortIdentifier(request.mutationId))",
                    error.localizedDescription
                ].joined(separator: " ")
            )
            throw error
        }
    }

    func updateItem(id itemId: Int, with draft: ShoppingItemDraft) async throws {
        try await updateItem(id: itemId, request: draft.updateRequest(actor: currentActorName))
    }

    func addBackToNeeded(_ item: ShoppingListItem, from draft: ShoppingItemDraft) async throws {
        try await updateItem(
            id: item.id,
            request: draft.addBackRequest(actor: currentActorName)
        )
    }

    func setPurchased(_ item: ShoppingListItem, purchased: Bool) async {
        do {
            try await updateItem(
                id: item.id,
                request: UpdateShoppingListItemRequest(purchased: purchased, actor: currentActorName)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func adjustQuantity(_ item: ShoppingListItem, by delta: Int) async {
        let nextQuantity = max(1, item.quantity + delta)

        guard nextQuantity != item.quantity else {
            return
        }

        do {
            try await updateItem(
                id: item.id,
                request: UpdateShoppingListItemRequest(quantity: nextQuantity, actor: currentActorName)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteItem(_ item: ShoppingListItem) async throws {
        guard !mutatingItemIDs.contains(item.id) else {
            return
        }

        mutatingItemIDs.insert(item.id)

        defer {
            mutatingItemIDs.remove(item.id)
        }

        let request = DeleteShoppingListItemRequest(actor: currentActorName)
        recordShoppingMutationLog(
            level: .info,
            title: "Deleting shopping item",
            detail: [
                "itemId=\(item.id)",
                "name=\(Self.logValue(item.name))",
                "mutationId=\(Self.shortIdentifier(request.mutationId))"
            ].joined(separator: " ")
        )

        do {
            let response = try await deleteShoppingListItem(item.id, request.mutationId, request.actor)
            items.removeAll { $0.id == response.itemId }
            generatedAt = response.generatedAt
            errorMessage = nil
            recordShoppingMutationLog(
                level: .success,
                title: "Shopping item deleted",
                detail: [
                    "itemId=\(response.itemId)",
                    "name=\(Self.logValue(response.item.name))",
                    "mutationId=\(Self.shortIdentifier(response.mutationId))"
                ].joined(separator: " ")
            )
        } catch {
            errorMessage = error.localizedDescription
            recordShoppingMutationLog(
                level: .error,
                title: "Shopping item delete failed",
                detail: [
                    "itemId=\(item.id)",
                    "name=\(Self.logValue(item.name))",
                    "mutationId=\(Self.shortIdentifier(request.mutationId))",
                    error.localizedDescription
                ].joined(separator: " ")
            )
            throw error
        }
    }

    @discardableResult
    private func load(isRefresh: Bool) async -> Bool {
        guard !isLoading, !isRefreshing else {
            return false
        }

        if isRefresh {
            isRefreshing = true
        } else {
            isLoading = true
        }

        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let response = try await loadShoppingList()
            applySnapshot(response)
            errorMessage = nil
            return true
        } catch {
            guard !error.isTaskCancellation else {
                return false
            }

            errorMessage = error.localizedDescription
            hasLoaded = true
            return false
        }
    }

    private func refreshFromLiveSnapshot() async {
        guard !isLoading, !isRefreshing, !isSyncingLiveSnapshot else {
            return
        }

        isSyncingLiveSnapshot = true

        defer {
            isSyncingLiveSnapshot = false
        }

        do {
            applySnapshot(try await loadShoppingList())
            errorMessage = nil
        } catch {
            // Keep the last confirmed snapshot visible. Pull-to-refresh remains the fallback.
        }
    }

    private func applySnapshot(_ response: ShoppingListResponse) {
        items = response.items
        stores = response.stores
        categories = response.categories
        generatedAt = response.generatedAt
        activeTrip = response.activeTrip
        hasLoaded = true
    }

    private func applyCommittedItem(_ item: ShoppingListItem) {
        if let existingIndex = items.firstIndex(where: { $0.id == item.id }) {
            guard shouldReplace(existing: items[existingIndex], with: item) else {
                return
            }

            items[existingIndex] = item
        } else {
            items.append(item)
        }
    }

    private func shouldReplace(existing: ShoppingListItem, with incoming: ShoppingListItem) -> Bool {
        guard let existingVersion = existing.version, let incomingVersion = incoming.version else {
            return true
        }

        return incomingVersion >= existingVersion
    }

    private func updateItem(id itemId: Int, request: UpdateShoppingListItemRequest) async throws {
        guard !mutatingItemIDs.contains(itemId) else {
            return
        }

        mutatingItemIDs.insert(itemId)

        defer {
            mutatingItemIDs.remove(itemId)
        }

        recordShoppingMutationLog(
            level: .info,
            title: "Updating shopping item",
            detail: [
                "itemId=\(itemId)",
                "mutationId=\(Self.shortIdentifier(request.mutationId))"
            ].joined(separator: " ")
        )

        do {
            let response = try await updateShoppingListItem(itemId, request)
            applyCommittedItem(response.item)
            generatedAt = response.generatedAt
            errorMessage = nil
            recordShoppingMutationLog(
                level: .success,
                title: "Shopping item updated",
                detail: [
                    "itemId=\(response.item.id)",
                    "name=\(Self.logValue(response.item.name))",
                    "mutationId=\(Self.shortIdentifier(response.mutationId))"
                ].joined(separator: " ")
            )
        } catch {
            errorMessage = error.localizedDescription
            recordShoppingMutationLog(
                level: .error,
                title: "Shopping item update failed",
                detail: [
                    "itemId=\(itemId)",
                    "mutationId=\(Self.shortIdentifier(request.mutationId))",
                    error.localizedDescription
                ].joined(separator: " ")
            )
            throw error
        }
    }

    private func recordShoppingMutationLog(
        level: AppLogLevel,
        title: String,
        detail: String
    ) {
        appLogStore?.record(
            level: level,
            category: "Shopping List",
            title: title,
            detail: detail
        )
    }

    private static func deduplicatedViewers(
        _ viewers: [ShoppingListViewerPresence]
    ) -> [ShoppingListViewerPresence] {
        var viewersById: [String: ShoppingListViewerPresence] = [:]

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

    private static func displayName(for viewer: ShoppingListViewerPresence) -> String {
        if let resident = residentIdentity(for: viewer) {
            return resident.rawValue
        }

        return "Someone"
    }

    private static func residentIdentity(for viewer: ShoppingListViewerPresence) -> ResidentIdentity? {
        if let resident = residentIdentity(forViewerId: viewer.viewerId) {
            return resident
        }

        let trimmedDisplayName = viewer.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let resident = ResidentIdentity(rawValue: trimmedDisplayName) {
            return resident
        }

        return nil
    }

    private static func displayName(forViewerId viewerId: String) -> String {
        if let resident = residentIdentity(forViewerId: viewerId) {
            return resident.rawValue
        }

        return "You"
    }

    private static func residentIdentity(forViewerId viewerId: String) -> ResidentIdentity? {
        let normalizedViewerId = viewerId.lowercased()

        if let resident = ResidentIdentity.allCases.first(where: { $0.shoppingListViewerId == normalizedViewerId }) {
            return resident
        }

        return nil
    }

    private static func shortIdentifier(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmedValue.prefix(12))
    }

    private static func logValue(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\"\(trimmedValue)\""
    }
}
