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
    typealias ShoppingStockPriceCheckStarter = (StartShoppingStockPriceCheckRequest) async throws -> ShoppingStockPriceCheckStartResult
    typealias ShoppingStockPriceCheckLoader = (String) async throws -> ShoppingStockPriceCheckSummary
    typealias ShoppingStockPriceCheckReadinessLoader = () async throws -> ShoppingStockPriceCheckReadiness
    typealias ShoppingStockPriceCheckSleeper = (UInt64) async throws -> Void
    typealias ShoppingListReaddStarter = (StartShoppingListReaddRequest) async throws -> ShoppingListReaddStartResult
    typealias ShoppingListReaddLoader = (String) async throws -> ShoppingListReaddSummary
    typealias ShoppingListReaddUndoer = (String) async throws -> ShoppingListReaddSummary
    typealias ShoppingListReaddReadinessLoader = () async throws -> ShoppingListReaddReadiness
    typealias ShoppingListReaddSleeper = (UInt64) async throws -> Void

    private struct ShoppingItemUpdateOutcome {
        let response: ShoppingListMutationResponse
        let activeTripRevisionBaseline: UInt64
    }

    private struct ActiveTripDisplayClaimCacheEntry {
        let key: String
        let disposition: ShoppingTripDisplayDisposition
    }

    private struct ActiveTripDisplayClaimInFlight {
        let key: String
        let task: Task<ShoppingTripDisplayDisposition?, Never>
    }

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
    @Published private(set) var stockPriceCheckJob: ShoppingStockPriceCheckSummary?
    @Published private(set) var stockPriceCheckReadiness: ShoppingStockPriceCheckReadiness?
    @Published private(set) var stockPriceCheckErrorMessage: String?
    @Published private(set) var finalStockPriceCheckSummary: ShoppingStockPriceCheckSummary?
    @Published private(set) var isStartingStockPriceCheck = false
    @Published private(set) var shoppingListReaddRun: ShoppingListReaddSummary?
    @Published private(set) var shoppingListReaddReadiness: ShoppingListReaddReadiness?
    @Published private(set) var shoppingListReaddErrorMessage: String?
    @Published private(set) var finalShoppingListReaddSummary: ShoppingListReaddSummary?
    @Published private(set) var isStartingShoppingListReadd = false
    @Published private(set) var isUndoingShoppingListReadd = false

    private let loadShoppingList: ShoppingListLoader
    private let lookupShoppingListItem: ShoppingListLookup
    private let createShoppingListItem: ShoppingListCreator
    private let updateShoppingListItem: ShoppingListUpdater
    private let deleteShoppingListItem: ShoppingListDeleter
    private let startShoppingTrip: ShoppingTripStarter
    private let endShoppingTrip: ShoppingTripEnder
    private let claimShoppingTripDisplay: ShoppingTripDisplayClaimer
    private let startShoppingStockPriceCheck: ShoppingStockPriceCheckStarter
    private let fetchShoppingStockPriceCheck: ShoppingStockPriceCheckLoader
    private let fetchShoppingStockPriceCheckReadiness: ShoppingStockPriceCheckReadinessLoader
    private let stockPriceCheckSleep: ShoppingStockPriceCheckSleeper
    private let sendShoppingListReadd: ShoppingListReaddStarter
    private let loadShoppingListReadd: ShoppingListReaddLoader
    private let performShoppingListReaddUndo: ShoppingListReaddUndoer
    private let loadShoppingListReaddReadiness: ShoppingListReaddReadinessLoader
    private let shoppingListReaddSleep: ShoppingListReaddSleeper
    private let searchKrogerProducts: KrogerProductSearch?
    private let liveService: ShoppingListLiveServicing?
    private let appLogStore: AppLogStore?
    private let currentViewerId: String?
    private let currentActorName: String?
    private var hasLoaded = false
    private var isSyncingLiveSnapshot = false
    private var liveUpdatesTask: Task<Void, Never>?
    private var liveConnectionStateTask: Task<Void, Never>?
    private var committedStateRevision: UInt64 = 0
    private var activeTripRevision: UInt64 = 0
    private var stockPriceCheckPollingTask: Task<Void, Never>?
    private var stockPriceCheckPollingToken: UUID?
    private var isStockPriceCheckPollingAllowed = false
    private var isLoadingStockPriceCheckReadiness = false
    private var shoppingListReaddPollingTask: Task<Void, Never>?
    private var shoppingListReaddPollingToken: UUID?
    private var isShoppingListReaddPollingAllowed = false
    private var isLoadingShoppingListReaddReadiness = false
    private var activeTripDisplayClaimCache: ActiveTripDisplayClaimCacheEntry?
    private var activeTripDisplayClaimInFlight: ActiveTripDisplayClaimInFlight?

    private static let maximumStockPriceCheckPollAttempts = 30
    private static let stockPriceCheckPollDelaysNanoseconds: [UInt64] = [
        1_000_000_000,
        1_000_000_000,
        2_000_000_000,
        3_000_000_000,
        5_000_000_000
    ]
    private static let maximumShoppingListReaddPollAttempts = 30
    private static let shoppingListReaddPollDelaysNanoseconds: [UInt64] = [
        1_000_000_000,
        1_000_000_000,
        2_000_000_000,
        3_000_000_000,
        5_000_000_000
    ]

    var isEmpty: Bool {
        hasLoaded && items.isEmpty && errorMessage == nil && !isLoading
    }

    var isStockPriceCheckActive: Bool {
        guard let stockPriceCheckJob else {
            return false
        }

        switch stockPriceCheckJob.status {
        case .queued, .running, .unknown:
            return true
        case .completed, .completedWithIssues, .failed:
            return false
        }
    }

    var isStockPriceCheckUnavailable: Bool {
        stockPriceCheckReadiness?.enabled == false
    }

    var isShoppingListReaddActive: Bool {
        guard let shoppingListReaddRun else {
            return false
        }

        switch shoppingListReaddRun.status {
        case .queued, .matching, .applying, .unknown:
            return true
        case .completed, .completedWithIssues, .failed, .undone:
            return false
        }
    }

    /// This readiness is intentionally independent of the stock/price browser feature.
    var isShoppingListReaddUnavailable: Bool {
        shoppingListReaddReadiness?.ready == false
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
            },
            startShoppingStockPriceCheck: { request in
                try await apiClient.startShoppingStockPriceCheck(request)
            },
            fetchShoppingStockPriceCheck: { jobId in
                try await apiClient.fetchShoppingStockPriceCheck(id: jobId)
            },
            fetchShoppingStockPriceCheckReadiness: {
                try await apiClient.fetchShoppingStockPriceCheckReadiness()
            },
            startShoppingListReadd: { request in
                try await apiClient.startShoppingListReadd(request)
            },
            fetchShoppingListReadd: { runId in
                try await apiClient.fetchShoppingListReadd(id: runId)
            },
            undoShoppingListReadd: { runId in
                try await apiClient.undoShoppingListReadd(id: runId)
            },
            fetchShoppingListReaddReadiness: {
                try await apiClient.fetchShoppingListReaddReadiness()
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
            },
            startShoppingStockPriceCheck: { _ in
                throw APIError.transport("Stock and price checks are not configured.")
            },
            fetchShoppingStockPriceCheck: { _ in
                throw APIError.transport("Stock and price checks are not configured.")
            },
            fetchShoppingStockPriceCheckReadiness: {
                throw APIError.transport("Stock and price checks are not configured.")
            },
            startShoppingListReadd: { _ in
                throw APIError.transport("AI Shopping re-add is not configured.")
            },
            fetchShoppingListReadd: { _ in
                throw APIError.transport("AI Shopping re-add is not configured.")
            },
            undoShoppingListReadd: { _ in
                throw APIError.transport("AI Shopping re-add is not configured.")
            },
            fetchShoppingListReaddReadiness: {
                throw APIError.transport("AI Shopping re-add is not configured.")
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
        },
        startShoppingStockPriceCheck: @escaping ShoppingStockPriceCheckStarter = { _ in
            throw APIError.transport("Stock and price checks are not configured.")
        },
        fetchShoppingStockPriceCheck: @escaping ShoppingStockPriceCheckLoader = { _ in
            throw APIError.transport("Stock and price checks are not configured.")
        },
        fetchShoppingStockPriceCheckReadiness: @escaping ShoppingStockPriceCheckReadinessLoader = {
            throw APIError.transport("Stock and price checks are not configured.")
        },
        stockPriceCheckSleep: @escaping ShoppingStockPriceCheckSleeper = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        startShoppingListReadd: @escaping ShoppingListReaddStarter = { _ in
            throw APIError.transport("AI Shopping re-add is not configured.")
        },
        fetchShoppingListReadd: @escaping ShoppingListReaddLoader = { _ in
            throw APIError.transport("AI Shopping re-add is not configured.")
        },
        undoShoppingListReadd: @escaping ShoppingListReaddUndoer = { _ in
            throw APIError.transport("AI Shopping re-add is not configured.")
        },
        fetchShoppingListReaddReadiness: @escaping ShoppingListReaddReadinessLoader = {
            throw APIError.transport("AI Shopping re-add is not configured.")
        },
        shoppingListReaddSleep: @escaping ShoppingListReaddSleeper = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
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
        self.startShoppingStockPriceCheck = startShoppingStockPriceCheck
        self.fetchShoppingStockPriceCheck = fetchShoppingStockPriceCheck
        self.fetchShoppingStockPriceCheckReadiness = fetchShoppingStockPriceCheckReadiness
        self.stockPriceCheckSleep = stockPriceCheckSleep
        self.sendShoppingListReadd = startShoppingListReadd
        self.loadShoppingListReadd = fetchShoppingListReadd
        self.performShoppingListReaddUndo = undoShoppingListReadd
        self.loadShoppingListReaddReadiness = fetchShoppingListReaddReadiness
        self.shoppingListReaddSleep = shoppingListReaddSleep
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
        stockPriceCheckPollingTask?.cancel()
        shoppingListReaddPollingTask?.cancel()
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

    /// Starts or stops client-side monitoring only. The durable server job continues when this screen is not visible.
    func setStockPriceCheckPollingAllowed(_ allowed: Bool) {
        guard allowed else {
            isStockPriceCheckPollingAllowed = false
            stopStockPriceCheckPolling()
            return
        }

        guard !isStockPriceCheckPollingAllowed else {
            beginStockPriceCheckPollingIfNeeded()
            return
        }

        isStockPriceCheckPollingAllowed = true

        guard stockPriceCheckReadiness == nil else {
            beginStockPriceCheckPollingIfNeeded()
            return
        }

        guard !isLoadingStockPriceCheckReadiness else {
            return
        }

        isLoadingStockPriceCheckReadiness = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingStockPriceCheckReadiness = false }
            await self.refreshStockPriceCheckReadiness()
            self.beginStockPriceCheckPollingIfNeeded()
        }
    }

    func refreshStockPriceCheckReadiness() async {
        do {
            stockPriceCheckReadiness = try await fetchShoppingStockPriceCheckReadiness()
            if stockPriceCheckJob == nil {
                stockPriceCheckErrorMessage = nil
            }
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            // Readiness is advisory. It must not overwrite an existing job's poll/recovery state.
            if stockPriceCheckJob == nil {
                stockPriceCheckErrorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func startStockPriceCheck() async -> ShoppingStockPriceCheckSummary? {
        guard !isStartingStockPriceCheck, !isStockPriceCheckActive else {
            return stockPriceCheckJob
        }
        guard hasLoaded else {
            stockPriceCheckErrorMessage = "The shopping list is still loading. Try again in a moment."
            return nil
        }
        guard items.contains(where: { !$0.purchased }) else {
            stockPriceCheckErrorMessage = "Add at least one needed item before checking stock and price."
            return nil
        }
        guard let actor = currentActorName else {
            stockPriceCheckErrorMessage = "Choose Josh or Mallory before checking stock and price."
            return nil
        }
        guard stockPriceCheckReadiness?.enabled != false else {
            stockPriceCheckErrorMessage = "Stock and price checks are currently unavailable."
            return nil
        }

        isStartingStockPriceCheck = true
        defer { isStartingStockPriceCheck = false }

        do {
            let result = try await startShoppingStockPriceCheck(
                StartShoppingStockPriceCheckRequest(actor: actor)
            )
            let job = result.job
            adoptStockPriceCheck(job)
            stockPriceCheckErrorMessage = nil

            if isStockPriceCheckActive {
                beginStockPriceCheckPollingIfNeeded()
            } else {
                await finishStockPriceCheck(job)
            }

            return job
        } catch {
            guard !error.isTaskCancellation else {
                return nil
            }

            stockPriceCheckErrorMessage = error.localizedDescription
            return nil
        }
    }

    func stopStockPriceCheckPolling() {
        stockPriceCheckPollingTask?.cancel()
        stockPriceCheckPollingTask = nil
        stockPriceCheckPollingToken = nil
    }

    func dismissFinalStockPriceCheckSummary() {
        finalStockPriceCheckSummary = nil
    }

    /// Starts or stops local re-add polling. The server-owned run is never cancelled when this screen leaves view.
    func setShoppingListReaddPollingAllowed(_ allowed: Bool) {
        guard allowed else {
            isShoppingListReaddPollingAllowed = false
            stopShoppingListReaddPolling()
            return
        }

        guard !isShoppingListReaddPollingAllowed else {
            beginShoppingListReaddPollingIfNeeded()
            return
        }

        isShoppingListReaddPollingAllowed = true

        guard shoppingListReaddReadiness == nil else {
            beginShoppingListReaddPollingIfNeeded()
            return
        }

        guard !isLoadingShoppingListReaddReadiness else {
            return
        }

        isLoadingShoppingListReaddReadiness = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingShoppingListReaddReadiness = false }
            await self.refreshShoppingListReaddReadiness()
            self.beginShoppingListReaddPollingIfNeeded()
        }
    }

    func refreshShoppingListReaddReadiness() async {
        do {
            shoppingListReaddReadiness = try await loadShoppingListReaddReadiness()
            if shoppingListReaddRun == nil {
                shoppingListReaddErrorMessage = nil
            }
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            // Readiness is advisory and cannot replace an active durable run.
            if shoppingListReaddRun == nil {
                shoppingListReaddErrorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func startShoppingListReadd(
        text: String,
        mutationId: String = UUID().uuidString
    ) async -> ShoppingListReaddSummary? {
        guard !isStartingShoppingListReadd, !isShoppingListReaddActive else {
            return shoppingListReaddRun
        }
        guard hasLoaded else {
            shoppingListReaddErrorMessage = "The shopping list is still loading. Try again in a moment."
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            shoppingListReaddErrorMessage = "Enter at least one item to add."
            return nil
        }
        guard let actor = currentActorName else {
            shoppingListReaddErrorMessage = "Choose Josh or Mallory before adding items."
            return nil
        }
        guard shoppingListReaddReadiness?.ready != false else {
            shoppingListReaddErrorMessage = "AI Shopping re-add is currently unavailable."
            return nil
        }

        isStartingShoppingListReadd = true
        defer { isStartingShoppingListReadd = false }

        do {
            let result = try await sendShoppingListReadd(
                StartShoppingListReaddRequest(text: trimmedText, actor: actor, mutationId: mutationId)
            )
            let run = result.run
            adoptShoppingListReadd(run)
            shoppingListReaddErrorMessage = nil

            if isShoppingListReaddActive {
                beginShoppingListReaddPollingIfNeeded()
            } else {
                await finishShoppingListReadd(run)
            }

            return run
        } catch {
            guard !error.isTaskCancellation else {
                return nil
            }

            shoppingListReaddErrorMessage = error.localizedDescription
            return nil
        }
    }

    func stopShoppingListReaddPolling() {
        shoppingListReaddPollingTask?.cancel()
        shoppingListReaddPollingTask = nil
        shoppingListReaddPollingToken = nil
    }

    @discardableResult
    func undoCurrentShoppingListReadd() async -> ShoppingListReaddSummary? {
        guard !isUndoingShoppingListReadd,
              let run = shoppingListReaddRun,
              run.undo.available else {
            return nil
        }

        isUndoingShoppingListReadd = true
        defer { isUndoingShoppingListReadd = false }

        do {
            let undone = try await performShoppingListReaddUndo(run.id)
            adoptShoppingListReadd(undone)
            finalShoppingListReaddSummary = undone
            shoppingListReaddErrorMessage = nil
            await refresh()
            return undone
        } catch {
            guard !error.isTaskCancellation else {
                return nil
            }

            shoppingListReaddErrorMessage = error.localizedDescription
            return nil
        }
    }

    func dismissFinalShoppingListReaddSummary() {
        finalShoppingListReaddSummary = nil
    }

    var stockPriceCheckProgressLabel: String? {
        guard let stockPriceCheckJob, isStockPriceCheckActive else {
            return nil
        }

        return "\(min(stockPriceCheckJob.processedItemCount, stockPriceCheckJob.requestedItemCount)) of \(stockPriceCheckJob.requestedItemCount)"
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
            let activeTripRevisionAtRequestStart = activeTripRevision
            let response = try await startShoppingTrip(
                StartShoppingTripRequest(actor: actor, originatingPushDeviceId: originatingPushDeviceId)
            )
            applyCommittedActiveTrip(
                response.activeTrip ?? response.trip,
                ifUnchangedSince: activeTripRevisionAtRequestStart
            )
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
            let activeTripRevisionAtRequestStart = activeTripRevision
            let response = try await endShoppingTrip(
                EndShoppingTripRequest(tripId: activeTrip.id, actor: actor)
            )
            applyCommittedActiveTrip(
                response.activeTrip,
                ifUnchangedSince: activeTripRevisionAtRequestStart
            )
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

        let claimKey = "\(activeTrip.id)|\(pushDeviceId)"
        if let cached = activeTripDisplayClaimCache, cached.key == claimKey {
            return cached.disposition
        }

        if let inFlight = activeTripDisplayClaimInFlight, inFlight.key == claimKey {
            let disposition = await inFlight.task.value
            return self.activeTrip?.id == activeTrip.id ? disposition : nil
        }

        let tripId = activeTrip.id
        let request = ClaimShoppingTripDisplayRequest(actor: actor, pushDeviceId: pushDeviceId)
        let claimer = claimShoppingTripDisplay
        let task = Task<ShoppingTripDisplayDisposition?, Never> {
            do {
                return try await claimer(tripId, request).displayDisposition
            } catch {
                // The shared trip remains usable when display recovery is unavailable.
                return nil
            }
        }
        activeTripDisplayClaimInFlight = ActiveTripDisplayClaimInFlight(key: claimKey, task: task)

        let disposition = await task.value
        if activeTripDisplayClaimInFlight?.key == claimKey {
            activeTripDisplayClaimInFlight = nil
        }

        guard self.activeTrip?.id == tripId else {
            return nil
        }

        if let disposition {
            activeTripDisplayClaimCache = ActiveTripDisplayClaimCacheEntry(
                key: claimKey,
                disposition: disposition
            )
        }

        return disposition
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
            removeCommittedItem(id: itemId)
        case .storesChanged(let stores, _, _):
            guard self.stores != stores else { return }
            self.stores = stores
            committedStateRevision &+= 1
        case .categoriesChanged(let categories, _, _):
            guard self.categories != categories else { return }
            self.categories = categories
            committedStateRevision &+= 1
        case .tripStarted(let trip, _, _), .tripUpdated(let trip, _, _):
            applyCommittedActiveTrip(trip, recordsAuthoritativeEvent: true)
        case .tripEnded:
            applyCommittedActiveTrip(nil, recordsAuthoritativeEvent: true)
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
            let activeTripRevisionAtRequestStart = activeTripRevision
            let response = try await createShoppingListItem(request)
            applyCommittedItem(response.item)
            generatedAt = response.generatedAt
            applyCommittedActiveTrip(
                response.activeTrip,
                ifUnchangedSince: activeTripRevisionAtRequestStart
            )
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

    func updateItem(_ item: ShoppingListItem, with draft: ShoppingItemDraft) async throws {
        let request = draft.updateRequest(comparedTo: item, actor: currentActorName)

        guard request.hasMutableFields else {
            return
        }

        _ = try await updateItem(id: item.id, request: request)
    }

    func addBackToNeeded(_ item: ShoppingListItem, from draft: ShoppingItemDraft) async throws {
        _ = try await updateItem(
            id: item.id,
            request: draft.addBackRequest(actor: currentActorName)
        )
    }

    @discardableResult
    func setPurchased(_ item: ShoppingListItem, purchased: Bool) async -> ShoppingTrip? {
        do {
            _ = try await updateItem(
                id: item.id,
                request: UpdateShoppingListItemRequest(purchased: purchased, actor: currentActorName)
            )
            return activeTrip
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func adjustQuantity(_ item: ShoppingListItem, by delta: Int) async {
        let nextQuantity = max(1, item.quantity + delta)

        guard nextQuantity != item.quantity else {
            return
        }

        do {
            _ = try await updateItem(
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
            let activeTripRevisionAtRequestStart = activeTripRevision
            let response = try await deleteShoppingListItem(item.id, request.mutationId, request.actor)
            removeCommittedItem(id: response.itemId)
            generatedAt = response.generatedAt
            applyCommittedActiveTrip(
                response.activeTrip,
                ifUnchangedSince: activeTripRevisionAtRequestStart
            )
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
        guard !isLoading, !isRefreshing, !isSyncingLiveSnapshot else {
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
            for _ in 0..<2 {
                let revisionAtRequestStart = committedStateRevision
                let response = try await loadShoppingList()

                if applySnapshot(response, ifUnchangedSince: revisionAtRequestStart) {
                    break
                }
            }

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
            for _ in 0..<2 {
                let revisionAtRequestStart = committedStateRevision

                if applySnapshot(
                    try await loadShoppingList(),
                    ifUnchangedSince: revisionAtRequestStart
                ) {
                    break
                }
            }

            errorMessage = nil
        } catch {
            // Keep the last confirmed snapshot visible. Pull-to-refresh remains the fallback.
        }
    }

    @discardableResult
    private func applySnapshot(
        _ response: ShoppingListResponse,
        ifUnchangedSince revisionAtRequestStart: UInt64
    ) -> Bool {
        guard committedStateRevision == revisionAtRequestStart else {
            hasLoaded = true
            return false
        }

        let previousTripId = activeTrip?.id
        let didChangeCommittedState = items != response.items
            || stores != response.stores
            || categories != response.categories
            || activeTrip != response.activeTrip
        let didChangeActiveTrip = activeTrip != response.activeTrip

        items = response.items
        stores = response.stores
        categories = response.categories
        generatedAt = response.generatedAt
        activeTrip = response.activeTrip

        if previousTripId != activeTrip?.id {
            activeTripDisplayClaimCache = nil
        }

        if didChangeActiveTrip {
            activeTripRevision &+= 1
        }

        if didChangeCommittedState {
            committedStateRevision &+= 1
        }

        hasLoaded = true
        return true
    }

    private func beginStockPriceCheckPollingIfNeeded() {
        guard isStockPriceCheckPollingAllowed,
              isStockPriceCheckActive,
              stockPriceCheckPollingTask == nil,
              let jobId = stockPriceCheckJob?.id else {
            return
        }

        let pollingToken = UUID()
        stockPriceCheckPollingToken = pollingToken
        stockPriceCheckPollingTask = Task { [weak self] in
            await self?.pollStockPriceCheck(id: jobId, pollingToken: pollingToken)
        }
    }

    private func beginShoppingListReaddPollingIfNeeded() {
        guard isShoppingListReaddPollingAllowed,
              isShoppingListReaddActive,
              shoppingListReaddPollingTask == nil,
              let runId = shoppingListReaddRun?.id else {
            return
        }

        let pollingToken = UUID()
        shoppingListReaddPollingToken = pollingToken
        shoppingListReaddPollingTask = Task { [weak self] in
            await self?.pollShoppingListReadd(id: runId, pollingToken: pollingToken)
        }
    }

    private func pollShoppingListReadd(id runId: String, pollingToken: UUID) async {
        defer {
            if shoppingListReaddPollingToken == pollingToken {
                shoppingListReaddPollingTask = nil
                shoppingListReaddPollingToken = nil
            }
        }

        var attempt = 0
        while isShoppingListReaddPollingAllowed,
              !Task.isCancelled,
              shoppingListReaddPollingToken == pollingToken,
              isShoppingListReaddActive,
              shoppingListReaddRun?.id == runId {
            if attempt > 0 {
                let delayIndex = min(attempt - 1, Self.shoppingListReaddPollDelaysNanoseconds.count - 1)
                do {
                    try await shoppingListReaddSleep(Self.shoppingListReaddPollDelaysNanoseconds[delayIndex])
                } catch {
                    return
                }
            }

            guard !Task.isCancelled,
                  isShoppingListReaddPollingAllowed,
                  shoppingListReaddPollingToken == pollingToken else {
                return
            }

            do {
                let run = try await loadShoppingListReadd(runId)
                guard !Task.isCancelled,
                      shoppingListReaddPollingToken == pollingToken,
                      run.id == runId,
                      shoppingListReaddRun?.id == runId else {
                    return
                }

                adoptShoppingListReadd(run)
                shoppingListReaddErrorMessage = nil

                if !isShoppingListReaddActive {
                    await finishShoppingListReadd(run)
                    return
                }

                attempt += 1
                if attempt >= Self.maximumShoppingListReaddPollAttempts {
                    shoppingListReaddErrorMessage = "AI Shopping re-add updates paused. Return to Shopping to try again."
                    return
                }
            } catch {
                guard !error.isTaskCancellation else {
                    return
                }

                shoppingListReaddErrorMessage = error.localizedDescription
                return
            }
        }
    }

    private func pollStockPriceCheck(id jobId: String, pollingToken: UUID) async {
        defer {
            if stockPriceCheckPollingToken == pollingToken {
                stockPriceCheckPollingTask = nil
                stockPriceCheckPollingToken = nil
            }
        }

        var attempt = 0

        while isStockPriceCheckPollingAllowed,
              !Task.isCancelled,
              stockPriceCheckPollingToken == pollingToken,
              isStockPriceCheckActive,
              stockPriceCheckJob?.id == jobId {
            if attempt > 0 {
                let delayIndex = min(attempt - 1, Self.stockPriceCheckPollDelaysNanoseconds.count - 1)

                do {
                    try await stockPriceCheckSleep(Self.stockPriceCheckPollDelaysNanoseconds[delayIndex])
                } catch {
                    return
                }
            }

            guard !Task.isCancelled,
                  isStockPriceCheckPollingAllowed,
                  stockPriceCheckPollingToken == pollingToken else {
                return
            }

            do {
                let job = try await fetchShoppingStockPriceCheck(jobId)

                guard !Task.isCancelled,
                      stockPriceCheckPollingToken == pollingToken,
                      job.id == jobId else {
                    guard !Task.isCancelled,
                          stockPriceCheckPollingToken == pollingToken else {
                        return
                    }

                    stockPriceCheckErrorMessage = "The stock and price check could not be refreshed safely."
                    return
                }

                adoptStockPriceCheck(job)
                stockPriceCheckErrorMessage = nil

                if !isStockPriceCheckActive {
                    await finishStockPriceCheck(job)
                    return
                }

                attempt += 1

                if attempt >= Self.maximumStockPriceCheckPollAttempts {
                    stockPriceCheckErrorMessage = "Stock and price check updates paused. Return to Shopping to try again."
                    return
                }
            } catch {
                guard !error.isTaskCancellation else {
                    return
                }

                stockPriceCheckErrorMessage = error.localizedDescription
                return
            }
        }
    }

    private func adoptStockPriceCheck(_ job: ShoppingStockPriceCheckSummary) {
        stockPriceCheckJob = job

        if isStockPriceCheckActive {
            finalStockPriceCheckSummary = nil
        }
    }

    private func finishStockPriceCheck(_ job: ShoppingStockPriceCheckSummary) async {
        finalStockPriceCheckSummary = job
        await refresh()
    }

    private func adoptShoppingListReadd(_ run: ShoppingListReaddSummary) {
        shoppingListReaddRun = run
        if isShoppingListReaddActive {
            finalShoppingListReaddSummary = nil
        }
    }

    private func finishShoppingListReadd(_ run: ShoppingListReaddSummary) async {
        finalShoppingListReaddSummary = run
        await refresh()
    }

    private func applyCommittedItem(_ item: ShoppingListItem) {
        if let existingIndex = items.firstIndex(where: { $0.id == item.id }) {
            guard shouldReplace(existing: items[existingIndex], with: item) else {
                return
            }

            guard items[existingIndex] != item else {
                return
            }

            items[existingIndex] = item
        } else {
            items.append(item)
        }

        committedStateRevision &+= 1
    }

    private func removeCommittedItem(id itemId: Int) {
        guard items.contains(where: { $0.id == itemId }) else {
            return
        }

        items.removeAll { $0.id == itemId }
        committedStateRevision &+= 1
    }

    private func applyCommittedActiveTrip(
        _ trip: ShoppingTrip?,
        ifUnchangedSince expectedRevision: UInt64? = nil,
        recordsAuthoritativeEvent: Bool = false
    ) {
        if let expectedRevision, activeTripRevision != expectedRevision {
            return
        }

        if let activeTrip,
           let trip,
           activeTrip.id == trip.id,
           trip.version < activeTrip.version {
            return
        }

        guard activeTrip != trip else {
            if recordsAuthoritativeEvent {
                activeTripRevision &+= 1
                committedStateRevision &+= 1
            }

            return
        }

        let previousTripId = activeTrip?.id
        activeTrip = trip
        if previousTripId != trip?.id {
            activeTripDisplayClaimCache = nil
        }
        activeTripRevision &+= 1
        committedStateRevision &+= 1
    }

    private func shouldReplace(existing: ShoppingListItem, with incoming: ShoppingListItem) -> Bool {
        guard let existingVersion = existing.version, let incomingVersion = incoming.version else {
            return true
        }

        return incomingVersion >= existingVersion
    }

    private func updateItem(id itemId: Int, request: UpdateShoppingListItemRequest) async throws -> ShoppingListMutationResponse {
        guard !mutatingItemIDs.contains(itemId) else {
            throw APIError.transport("This shopping item is already being updated.")
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
            let outcome = try await updateShoppingItemWithRecovery(itemId: itemId, request: request)
            let response = outcome.response
            applyCommittedItem(response.item)
            generatedAt = response.generatedAt
            applyCommittedActiveTrip(
                response.activeTrip,
                ifUnchangedSince: outcome.activeTripRevisionBaseline
            )
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
            return response
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

    private func updateShoppingItemWithRecovery(
        itemId: Int,
        request: UpdateShoppingListItemRequest
    ) async throws -> ShoppingItemUpdateOutcome {
        let initialActiveTripRevision = activeTripRevision

        do {
            return ShoppingItemUpdateOutcome(
                response: try await updateShoppingListItem(itemId, request),
                activeTripRevisionBaseline: initialActiveTripRevision
            )
        } catch {
            guard Self.isTransportFailure(error) else {
                throw error
            }
            let transportError = error

            recordShoppingMutationLog(
                level: .warning,
                title: "Reconciling shopping item update",
                detail: [
                    "itemId=\(itemId)",
                    "mutationId=\(Self.shortIdentifier(request.mutationId))",
                    error.localizedDescription
                ].joined(separator: " ")
            )

            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                throw CancellationError()
            }

            if let committedItem = items.first(where: { $0.id == itemId }),
               request.isReflected(in: committedItem) {
                return ShoppingItemUpdateOutcome(
                    response: reconciledMutationResponse(item: committedItem, request: request),
                    activeTripRevisionBaseline: activeTripRevision
                )
            }

            var didConfirmUncommitted = false

            for _ in 0..<2 {
                let revisionAtRequestStart = committedStateRevision
                let snapshot: ShoppingListResponse

                do {
                    snapshot = try await loadShoppingList()
                } catch {
                    if error.isTaskCancellation {
                        throw CancellationError()
                    }

                    throw transportError
                }

                let didApplySnapshot = applySnapshot(
                    snapshot,
                    ifUnchangedSince: revisionAtRequestStart
                )

                if let snapshotItem = snapshot.items.first(where: { $0.id == itemId }),
                   request.isReflected(in: snapshotItem) {
                    if didApplySnapshot {
                        return ShoppingItemUpdateOutcome(
                            response: ShoppingListMutationResponse(
                                ok: true,
                                item: snapshotItem,
                                activeTrip: snapshot.activeTrip,
                                mutationId: request.mutationId,
                                generatedAt: snapshot.generatedAt
                            ),
                            activeTripRevisionBaseline: activeTripRevision
                        )
                    }

                    if let currentItem = items.first(where: { $0.id == itemId }),
                       shouldReplace(existing: currentItem, with: snapshotItem) {
                        return ShoppingItemUpdateOutcome(
                            response: reconciledMutationResponse(item: snapshotItem, request: request),
                            activeTripRevisionBaseline: activeTripRevision
                        )
                    }
                }

                if didApplySnapshot {
                    didConfirmUncommitted = true
                    break
                }

                if let committedItem = items.first(where: { $0.id == itemId }),
                   request.isReflected(in: committedItem) {
                    return ShoppingItemUpdateOutcome(
                        response: reconciledMutationResponse(item: committedItem, request: request),
                        activeTripRevisionBaseline: activeTripRevision
                    )
                }
            }

            guard didConfirmUncommitted else {
                throw transportError
            }

            recordShoppingMutationLog(
                level: .warning,
                title: "Retrying shopping item update",
                detail: [
                    "itemId=\(itemId)",
                    "mutationId=\(Self.shortIdentifier(request.mutationId))"
                ].joined(separator: " ")
            )

            let retryActiveTripRevision = activeTripRevision
            return ShoppingItemUpdateOutcome(
                response: try await updateShoppingListItem(itemId, request),
                activeTripRevisionBaseline: retryActiveTripRevision
            )
        }
    }

    private func reconciledMutationResponse(
        item: ShoppingListItem,
        request: UpdateShoppingListItemRequest
    ) -> ShoppingListMutationResponse {
        ShoppingListMutationResponse(
            ok: true,
            item: item,
            activeTrip: activeTrip,
            mutationId: request.mutationId,
            generatedAt: generatedAt
        )
    }

    private static func isTransportFailure(_ error: Error) -> Bool {
        if let apiError = error as? APIError,
           case .transport = apiError {
            return true
        }

        return error is URLError && !error.isTaskCancellation
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
