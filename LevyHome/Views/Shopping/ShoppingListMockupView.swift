import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShoppingListMockupView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @AppStorage(ResidentPreference.storageKey) private var currentResidentName = ResidentPreference.defaultName

    var body: some View {
        let viewerIdentity = ShoppingListViewerIdentity.forResidentPreference(currentResidentName)

        ShoppingListContentView(
            viewModel: ShoppingListViewModel(
                apiClient: appEnvironment.apiClient,
                liveService: ShoppingListLiveService(
                    baseURL: appEnvironment.config.apiBaseURL,
                    viewerIdentity: viewerIdentity,
                    appLogStore: appEnvironment.appLogStore
                ),
                currentViewerId: viewerIdentity.viewerId
            )
        )
        .id(viewerIdentity.viewerId)
    }
}

private extension ShoppingListViewerIdentity {
    static func forResidentPreference(
        _ residentName: String,
        userDefaults: UserDefaults = .standard
    ) -> ShoppingListViewerIdentity {
        let deviceName = currentDeviceName

        if let resident = ResidentIdentity(rawValue: residentName) {
            return ShoppingListViewerIdentity(
                viewerId: resident.shoppingListViewerId,
                displayName: resident.rawValue,
                deviceName: deviceName
            )
        }

        if let deviceName,
           let inferredResident = ResidentIdentity.inferred(from: deviceName) {
            return ShoppingListViewerIdentity(
                viewerId: inferredResident.shoppingListViewerId,
                displayName: inferredResident.rawValue,
                deviceName: deviceName
            )
        }

        return ShoppingListViewerIdentity(
            viewerId: stableViewerId(userDefaults: userDefaults),
            displayName: deviceName ?? "This device",
            deviceName: deviceName
        )
    }

    private static func stableViewerId(userDefaults: UserDefaults) -> String {
        let key = "shoppingList.viewerId"

        if let existingId = userDefaults.string(forKey: key), !existingId.isEmpty {
            return existingId
        }

        let newId = "ios-\(UUID().uuidString.lowercased())"
        userDefaults.set(newId, forKey: key)
        return newId
    }

    private static var currentDeviceName: String? {
        #if canImport(UIKit)
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
        #else
        return nil
        #endif
    }
}

private extension ResidentIdentity {
    var shoppingListViewerId: String {
        switch self {
        case .josh:
            return "josh"
        case .mallory:
            return "mallory"
        }
    }
}

@MainActor
final class ShoppingListViewModel: ObservableObject {
    typealias ShoppingListLoader = () async throws -> ShoppingListResponse
    typealias ShoppingListLookup = (String) async throws -> ShoppingListItemLookupResponse
    typealias ShoppingListCreator = (CreateShoppingListItemRequest) async throws -> ShoppingListMutationResponse
    typealias ShoppingListUpdater = (Int, UpdateShoppingListItemRequest) async throws -> ShoppingListMutationResponse
    typealias ShoppingListDeleter = (Int) async throws -> DeleteShoppingListItemResponse

    @Published private(set) var items: [ShoppingListItem] = []
    @Published private(set) var stores: [ShoppingStore] = []
    @Published private(set) var categories: [ShoppingCategory] = []
    @Published private(set) var activeViewers: [ShoppingListViewerPresence] = []
    @Published private(set) var generatedAt: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCreatingItem = false
    @Published private(set) var mutatingItemIDs: Set<Int> = []

    private let loadShoppingList: ShoppingListLoader
    private let lookupShoppingListItem: ShoppingListLookup
    private let createShoppingListItem: ShoppingListCreator
    private let updateShoppingListItem: ShoppingListUpdater
    private let deleteShoppingListItem: ShoppingListDeleter
    private let liveService: ShoppingListLiveServicing?
    private let currentViewerId: String?
    private var hasLoaded = false
    private var isSyncingLiveSnapshot = false
    private var liveUpdatesTask: Task<Void, Never>?

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

    convenience init(
        apiClient: APIClient,
        liveService: ShoppingListLiveServicing? = nil,
        currentViewerId: String? = nil
    ) {
        self.init(
            liveService: liveService,
            currentViewerId: currentViewerId,
            loadShoppingList: {
                try await apiClient.fetchShoppingList()
            },
            lookupShoppingListItem: { name in
                try await apiClient.lookupShoppingListItem(named: name)
            },
            createShoppingListItem: { request in
                try await apiClient.createShoppingListItem(request)
            },
            updateShoppingListItem: { itemId, request in
                try await apiClient.updateShoppingListItem(id: itemId, request)
            },
            deleteShoppingListItem: { itemId in
                try await apiClient.deleteShoppingListItem(id: itemId)
            }
        )
    }

    init(
        liveService: ShoppingListLiveServicing? = nil,
        currentViewerId: String? = nil,
        loadShoppingList: @escaping ShoppingListLoader
    ) {
        self.init(
            liveService: liveService,
            currentViewerId: currentViewerId,
            loadShoppingList: loadShoppingList,
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in
                throw APIError.transport("Shopping list creation is not configured.")
            },
            updateShoppingListItem: { _, _ in
                throw APIError.transport("Shopping list updates are not configured.")
            },
            deleteShoppingListItem: { _ in
                throw APIError.transport("Shopping list deletion is not configured.")
            }
        )
    }

    init(
        liveService: ShoppingListLiveServicing? = nil,
        currentViewerId: String? = nil,
        loadShoppingList: @escaping ShoppingListLoader,
        lookupShoppingListItem: @escaping ShoppingListLookup,
        createShoppingListItem: @escaping ShoppingListCreator,
        updateShoppingListItem: @escaping ShoppingListUpdater,
        deleteShoppingListItem: @escaping ShoppingListDeleter
    ) {
        self.loadShoppingList = loadShoppingList
        self.lookupShoppingListItem = lookupShoppingListItem
        self.createShoppingListItem = createShoppingListItem
        self.updateShoppingListItem = updateShoppingListItem
        self.deleteShoppingListItem = deleteShoppingListItem
        self.liveService = liveService
        self.currentViewerId = currentViewerId
    }

    deinit {
        liveUpdatesTask?.cancel()
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

    func startLiveUpdatesIfNeeded() {
        guard liveUpdatesTask == nil, let liveService else {
            return
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
        liveService?.disconnect()
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

    fileprivate func createItem(from draft: ShoppingItemDraft) async throws {
        guard !isCreatingItem else {
            return
        }

        isCreatingItem = true

        defer {
            isCreatingItem = false
        }

        do {
            let response = try await createShoppingListItem(draft.createRequest())
            applyCommittedItem(response.item)
            generatedAt = response.generatedAt
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    fileprivate func updateItem(id itemId: Int, with draft: ShoppingItemDraft) async throws {
        try await updateItem(id: itemId, request: draft.updateRequest())
    }

    fileprivate func addBackToNeeded(_ item: ShoppingListItem, from draft: ShoppingItemDraft) async throws {
        try await updateItem(
            id: item.id,
            request: draft.addBackRequest()
        )
    }

    func setPurchased(_ item: ShoppingListItem, purchased: Bool) async {
        do {
            try await updateItem(
                id: item.id,
                request: UpdateShoppingListItemRequest(purchased: purchased)
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
                request: UpdateShoppingListItemRequest(quantity: nextQuantity)
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

        do {
            let response = try await deleteShoppingListItem(item.id)
            items.removeAll { $0.id == response.itemId }
            generatedAt = response.generatedAt
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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

        do {
            let response = try await updateShoppingListItem(itemId, request)
            applyCommittedItem(response.item)
            generatedAt = response.generatedAt
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
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
        let normalizedViewerId = viewer.viewerId.lowercased()

        if let resident = ResidentIdentity.allCases.first(where: { $0.shoppingListViewerId == normalizedViewerId }) {
            return resident.rawValue
        }

        let trimmedDisplayName = viewer.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let resident = ResidentIdentity(rawValue: trimmedDisplayName) {
            return resident.rawValue
        }

        return "Someone"
    }
}

fileprivate enum ShoppingItemEditorMode: Identifiable, Equatable {
    case add
    case edit(ShoppingListItem)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let item):
            return "edit-\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .add:
            return "Add Item"
        case .edit:
            return "Edit Item"
        }
    }

    var editingItemID: Int? {
        switch self {
        case .add:
            return nil
        case .edit(let item):
            return item.id
        }
    }

    var editingItem: ShoppingListItem? {
        switch self {
        case .add:
            return nil
        case .edit(let item):
            return item
        }
    }
}

fileprivate struct ShoppingItemDraft: Equatable {
    var name: String
    var brand: String
    var quantity: Int
    var notes: String
    var selectedCategoryId: Int?
    var selectedStoreIds: Set<Int>
    var purchased: Bool

    init(
        name: String = "",
        brand: String = "",
        quantity: Int = 1,
        notes: String = "",
        selectedCategoryId: Int? = nil,
        selectedStoreIds: Set<Int> = [],
        purchased: Bool = false
    ) {
        self.name = name
        self.brand = brand
        self.quantity = max(1, quantity)
        self.notes = notes
        self.selectedCategoryId = selectedCategoryId
        self.selectedStoreIds = selectedStoreIds
        self.purchased = purchased
    }

    init(item: ShoppingListItem) {
        self.init(
            name: item.name,
            brand: item.brand ?? "",
            quantity: item.quantity,
            notes: item.notes ?? "",
            selectedCategoryId: item.categoryId,
            selectedStoreIds: Set(item.storeIds),
            purchased: item.purchased
        )
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty
    }

    mutating func adjustQuantity(by delta: Int) {
        quantity = max(1, quantity + delta)
    }

    func createRequest() -> CreateShoppingListItemRequest {
        CreateShoppingListItemRequest(
            name: trimmedName,
            brand: normalizedOptionalText(brand),
            quantity: quantity,
            notes: normalizedOptionalText(notes),
            purchased: purchased,
            storeIds: sortedStoreIds,
            categoryId: selectedCategoryId
        )
    }

    func updateRequest() -> UpdateShoppingListItemRequest {
        UpdateShoppingListItemRequest(
            name: trimmedName,
            brand: nullableString(brand),
            quantity: quantity,
            notes: nullableString(notes),
            purchased: purchased,
            storeIds: sortedStoreIds,
            categoryId: nullableCategoryId
        )
    }

    func addBackRequest() -> UpdateShoppingListItemRequest {
        UpdateShoppingListItemRequest(
            quantity: quantity,
            notes: optionalNullableString(notes),
            purchased: false,
            storeIds: selectedStoreIds.isEmpty ? nil : sortedStoreIds,
            categoryId: selectedCategoryId.map { .value($0) }
        )
    }

    private var sortedStoreIds: [Int] {
        selectedStoreIds.sorted()
    }

    private var nullableCategoryId: ShoppingListNullableValue<Int> {
        selectedCategoryId.map { .value($0) } ?? .null
    }

    private func nullableString(_ value: String) -> ShoppingListNullableValue<String> {
        normalizedOptionalText(value).map { .value($0) } ?? .null
    }

    private func optionalNullableString(_ value: String) -> ShoppingListNullableValue<String>? {
        normalizedOptionalText(value).map { .value($0) }
    }

    private func normalizedOptionalText(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

fileprivate enum ShoppingDuplicateStatus: Equatable {
    case alreadyNeeded(ShoppingListItem)
    case pickedUp(ShoppingListItem)

    var item: ShoppingListItem {
        switch self {
        case .alreadyNeeded(let item), .pickedUp(let item):
            return item
        }
    }
}

fileprivate func normalizedShoppingItemName(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

private struct ShoppingListContentView: View {
    @StateObject private var viewModel: ShoppingListViewModel
    @State private var searchText = ""
    @State private var selectedCategoryId: Int?
    @State private var editorMode: ShoppingItemEditorMode?
    @State private var pendingDeleteItem: ShoppingListItem?

    init(viewModel: ShoppingListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                if viewModel.isLoading {
                    loadingView
                } else {
                    contentView
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Shopping")
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorMode = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add shopping item")
            }
        }
        .sheet(item: $editorMode) { mode in
            ShoppingItemEditorSheet(
                mode: mode,
                viewModel: viewModel
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Delete Item?",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteItem = nil
                    }
                }
            ),
            presenting: pendingDeleteItem
        ) { item in
            Button("Delete", role: .destructive) {
                Task {
                    await delete(item)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteItem = nil
            }
        } message: { item in
            Text("Remove \(item.name) from the shared shopping list.")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        summaryPanel

        if let errorMessage = viewModel.errorMessage {
            ErrorBannerView(message: errorMessage)

            PrimaryActionButton(
                title: "Retry",
                systemImage: "arrow.clockwise"
            ) {
                Task {
                    await viewModel.refresh()
                }
            }
        }

        ShoppingListSearchField(searchText: $searchText)

        ShoppingCategoryFilterBar(
            selectedCategoryId: $selectedCategoryId,
            categories: filterCategories,
            counts: categoryCounts
        )

        if viewModel.isEmpty || groupedItems.isEmpty {
            emptyState
        } else {
            ForEach(groupedItems) { group in
                ShoppingCategorySection(
                    group: group,
                    mutatingItemIDs: viewModel.mutatingItemIDs,
                    onTogglePurchased: { item in
                        Task {
                            await viewModel.setPurchased(item, purchased: !item.purchased)
                        }
                    },
                    onAdjustQuantity: { item, delta in
                        Task {
                            await viewModel.adjustQuantity(item, by: delta)
                        }
                    },
                    onEdit: { item in
                        editorMode = .edit(item)
                    },
                    onDelete: { item in
                        pendingDeleteItem = item
                    }
                )
            }
        }
    }

    private var summaryPanel: some View {
        InfoPanel(
            title: "Grocery List",
            subtitle: "\(neededItemCount) \(neededItemCount == 1 ? "item" : "items") needed",
            systemImage: "cart"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(spacing: AppSpacing.medium) {
                    StatusBadgeView(label: "Database", systemImage: "externaldrive.connected.to.line.below", tone: .accent)
                    StatusBadgeView(label: "\(completedItemCount) picked up", systemImage: "checkmark.circle", tone: .success)

                    Spacer(minLength: 0)
                }

                if let otherActiveViewerLabel = viewModel.otherActiveViewerLabel {
                    StatusBadgeView(label: otherActiveViewerLabel, systemImage: "person.2", tone: .neutral)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: viewModel.otherActiveViewerLabel)
        }
    }

    private var loadingView: some View {
        InfoPanel(
            title: "Loading Shopping List",
            subtitle: "Fetching items from the database.",
            systemImage: "cart"
        ) {
            HStack(spacing: AppSpacing.medium) {
                ProgressView()

                Text("Checking the shared list...")
                    .font(.body)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyState: some View {
        InfoPanel(
            title: viewModel.items.isEmpty ? "No Shopping Items" : "No Matching Items",
            subtitle: viewModel.items.isEmpty ? "The database list is empty." : "Try a product name, store, or category.",
            systemImage: viewModel.items.isEmpty ? "cart" : "magnifyingglass"
        ) {
            if !searchText.isEmpty || selectedCategoryId != nil {
                Button {
                    searchText = ""
                    selectedCategoryId = nil
                } label: {
                    Label("Clear Filter", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var groupedItems: [ShoppingCategoryGroup] {
        let itemsByCategory = Dictionary(grouping: filteredItems, by: \.category)

        return filterCategories.compactMap { category in
            guard let items = itemsByCategory[category], !items.isEmpty else {
                return nil
            }

            return ShoppingCategoryGroup(category: category, items: items.sorted())
        }
    }

    private var filteredItems: [ShoppingListDisplayItem] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return displayItems
            .filter { displayItem in
                selectedCategoryId == nil || displayItem.category.id == selectedCategoryId
            }
            .filter { displayItem in
                guard !trimmedSearch.isEmpty else {
                    return true
                }

                return displayItem.matches(trimmedSearch)
            }
    }

    private var displayItems: [ShoppingListDisplayItem] {
        let categoriesById = Dictionary(uniqueKeysWithValues: viewModel.categories.map { ($0.id, $0) })
        let storesById = Dictionary(uniqueKeysWithValues: viewModel.stores.map { ($0.id, $0) })

        return viewModel.items.map { item in
            ShoppingListDisplayItem(
                item: item,
                category: category(for: item, categoriesById: categoriesById),
                stores: item.storeIds.map { storeId in
                    storesById[storeId] ?? ShoppingStore(id: storeId, name: "Store \(storeId)", logo: nil)
                }
            )
        }
    }

    private var filterCategories: [ShoppingCategory] {
        let responseCategories = viewModel.categories
        let categoriesById = Dictionary(uniqueKeysWithValues: responseCategories.map { ($0.id, $0) })
        let missingCategories = Set(viewModel.items.compactMap(\.categoryId))
            .filter { categoriesById[$0] == nil }
            .map { ShoppingCategory(id: $0, name: "Category \($0)") }
        let needsOther = viewModel.items.contains { $0.categoryId == nil }
        let allCategories = responseCategories
            + missingCategories
            + (needsOther ? [Self.uncategorizedCategory] : [])

        return allCategories.sorted { first, second in
            first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    private var categoryCounts: [ShoppingCategory: Int] {
        Dictionary(grouping: displayItems, by: \.category)
            .mapValues(\.count)
    }

    private var neededItemCount: Int {
        viewModel.items.filter { !$0.purchased }.count
    }

    private var completedItemCount: Int {
        viewModel.items.filter(\.purchased).count
    }

    private func category(
        for item: ShoppingListItem,
        categoriesById: [Int: ShoppingCategory]
    ) -> ShoppingCategory {
        guard let categoryId = item.categoryId else {
            return Self.uncategorizedCategory
        }

        return categoriesById[categoryId] ?? ShoppingCategory(id: categoryId, name: "Category \(categoryId)")
    }

    private static let uncategorizedCategory = ShoppingCategory(id: 0, name: "Other")

    private func delete(_ item: ShoppingListItem) async {
        defer {
            pendingDeleteItem = nil
        }

        do {
            try await viewModel.deleteItem(item)
        } catch {
            // The view model surfaces mutation failures in the existing error banner.
        }
    }
}

private struct ShoppingListSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(AppColors.mutedText)
                .frame(width: 24)

            TextField("Filter by item, store, or category", text: $searchText)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.mutedText)
                }
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(AppSpacing.medium)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ShoppingCategoryFilterBar: View {
    @Binding var selectedCategoryId: Int?
    let categories: [ShoppingCategory]
    let counts: [ShoppingCategory: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                filterButton(
                    title: "All",
                    systemImage: "square.grid.2x2",
                    count: counts.values.reduce(0, +),
                    isSelected: selectedCategoryId == nil
                ) {
                    selectedCategoryId = nil
                }

                ForEach(categories) { category in
                    filterButton(
                        title: category.name,
                        systemImage: category.systemImage,
                        count: counts[category] ?? 0,
                        isSelected: selectedCategoryId == category.id
                    ) {
                        selectedCategoryId = category.id
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func filterButton(
        title: String,
        systemImage: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.86) : AppColors.mutedText)
            }
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 36)
            .foregroundStyle(isSelected ? Color.white : AppColors.accent)
            .background(isSelected ? AppColors.accent : AppColors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ShoppingItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: ShoppingItemEditorMode
    @ObservedObject var viewModel: ShoppingListViewModel
    @State private var draft: ShoppingItemDraft
    @State private var serverDuplicate: ShoppingListItem?
    @State private var isCheckingDuplicate = false
    @State private var didFailDuplicateLookup = false
    @State private var formErrorMessage: String?
    @State private var isSubmitting = false
    @State private var isAddingBack = false
    @State private var pendingDeleteItem: ShoppingListItem?

    init(mode: ShoppingItemEditorMode, viewModel: ShoppingListViewModel) {
        self.mode = mode
        self.viewModel = viewModel
        _draft = State(initialValue: mode.editingItem.map(ShoppingItemDraft.init) ?? ShoppingItemDraft())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    nameField

                    duplicateStatusView

                    quantityControl

                    categoryPicker

                    storePicker

                    brandField

                    notesField

                    if let formErrorMessage {
                        ErrorBannerView(message: formErrorMessage)
                    }

                    PrimaryActionButton(
                        title: primaryButtonTitle,
                        systemImage: mode.editingItem == nil ? "plus" : "checkmark",
                        isLoading: isSubmitting,
                        isDisabled: isPrimaryDisabled
                    ) {
                        Task {
                            await submit()
                        }
                    }

                    if let editingItem = mode.editingItem {
                        Button(role: .destructive) {
                            pendingDeleteItem = editingItem
                        } label: {
                            Label("Delete Item", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isEditingItemMutating)
                    }
                }
                .padding(AppSpacing.screen)
            }
            .background(AppColors.pageBackground)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task(id: duplicateLookupKey) {
                await updateServerDuplicate(for: duplicateLookupKey)
            }
            .alert(
                "Delete Item?",
                isPresented: Binding(
                    get: { pendingDeleteItem != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeleteItem = nil
                        }
                    }
                ),
                presenting: pendingDeleteItem
            ) { item in
                Button("Delete", role: .destructive) {
                    Task {
                        await delete(item)
                    }
                }

                Button("Cancel", role: .cancel) {
                    pendingDeleteItem = nil
                }
            } message: { item in
                Text("Remove \(item.name) from the shared shopping list.")
            }
        }
    }

    private var nameField: some View {
        ShoppingFormSection(title: "What do we need?") {
            HStack(spacing: AppSpacing.medium) {
                TextField("Item name", text: $draft.name)
                    .font(.title2.weight(.semibold))
                    .submitLabel(.next)
                    .textInputAutocapitalization(.words)

                if !draft.name.isEmpty {
                    Button {
                        draft.name = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppColors.mutedText)
                    }
                    .accessibilityLabel("Clear item name")
                }
            }
            .padding(AppSpacing.medium)
            .background(AppColors.insetPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                    .stroke(AppColors.accent, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private var duplicateStatusView: some View {
        if let duplicateStatus {
            switch duplicateStatus {
            case .alreadyNeeded(let item):
                ErrorBannerView(
                    message: "Already on the list: \(duplicateSummary(for: item))",
                    tone: .warning
                )
            case .pickedUp(let item):
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    ErrorBannerView(
                        message: "Picked up before: \(duplicateSummary(for: item))",
                        tone: .info
                    )

                    Button {
                        Task {
                            await addBackToNeeded(item)
                        }
                    } label: {
                        Label("Add Back to Needed", systemImage: "arrow.uturn.left")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAddingBack || isSubmitting || viewModel.isMutatingItem(item.id))
                }
            }
        } else if isCheckingDuplicate {
            Label("Checking duplicates", systemImage: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(AppColors.mutedText)
        } else if didFailDuplicateLookup {
            ErrorBannerView(
                message: "Could not verify duplicates. The final save will still use the server check.",
                tone: .warning
            )
        }
    }

    private var quantityControl: some View {
        ShoppingFormSection(title: "Quantity") {
            HStack(spacing: AppSpacing.medium) {
                Button {
                    draft.adjustQuantity(by: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.headline.weight(.semibold))
                        .frame(width: 54, height: 44)
                }
                .disabled(draft.quantity <= 1)

                Spacer()

                Text("Qty \(draft.quantity)")
                    .font(.headline)
                    .monospacedDigit()

                Spacer()

                Button {
                    draft.adjustQuantity(by: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .frame(width: 54, height: 44)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 54)
            .foregroundStyle(AppColors.accent)
            .background(AppColors.insetPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                    .stroke(AppColors.panelBorder, lineWidth: 1)
            }
        }
    }

    private var categoryPicker: some View {
        ShoppingFormSection(title: "Category") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.small) {
                    ShoppingChoiceChip(
                        title: "None",
                        systemImage: "xmark.circle",
                        isSelected: draft.selectedCategoryId == nil
                    ) {
                        draft.selectedCategoryId = nil
                    }

                    ForEach(viewModel.categories) { category in
                        ShoppingChoiceChip(
                            title: category.name,
                            systemImage: category.systemImage,
                            isSelected: draft.selectedCategoryId == category.id
                        ) {
                            draft.selectedCategoryId = category.id
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var storePicker: some View {
        ShoppingFormSection(title: "Store") {
            if viewModel.stores.isEmpty {
                Text("No stores available")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.small) {
                        ForEach(viewModel.stores) { store in
                            ShoppingChoiceChip(
                                title: store.name,
                                systemImage: "mappin.circle",
                                isSelected: draft.selectedStoreIds.contains(store.id)
                            ) {
                                toggleStore(store)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var brandField: some View {
        ShoppingFormSection(title: "Brand") {
            TextField("Brand, optional", text: $draft.brand)
                .textInputAutocapitalization(.words)
                .padding(AppSpacing.medium)
                .background(AppColors.insetPanelBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                        .stroke(AppColors.panelBorder, lineWidth: 1)
                }
        }
    }

    private var notesField: some View {
        ShoppingFormSection(title: "Notes") {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: "pencil")
                    .font(.headline)
                    .foregroundStyle(AppColors.mutedText)
                    .frame(width: 24)

                TextField("Notes, optional", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
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

    private var primaryButtonTitle: String {
        switch mode {
        case .add:
            let name = draft.trimmedName
            return name.isEmpty ? "Add Item" : "Add \(name)"
        case .edit:
            return "Save Changes"
        }
    }

    private var isPrimaryDisabled: Bool {
        !draft.isValid
            || isSubmitting
            || isAddingBack
            || viewModel.isCreatingItem
            || isEditingItemMutating
            || duplicateStatus != nil
    }

    private var isEditingItemMutating: Bool {
        guard let editingItemID = mode.editingItemID else {
            return false
        }

        return viewModel.isMutatingItem(editingItemID)
    }

    private func duplicateSummary(for item: ShoppingListItem) -> String {
        var details = [
            item.name,
            "Qty \(item.quantity)",
        ]

        if let categoryName = categoryName(for: item) {
            details.append(categoryName)
        }

        return details.joined(separator: " - ")
    }

    private func categoryName(for item: ShoppingListItem) -> String? {
        guard let categoryId = item.categoryId else {
            return nil
        }

        return viewModel.categories.first { $0.id == categoryId }?.name ?? "Category \(categoryId)"
    }

    private var duplicateLookupKey: String {
        normalizedShoppingItemName(draft.name)
    }

    private var duplicateStatus: ShoppingDuplicateStatus? {
        guard let duplicateItem = localDuplicate ?? filteredServerDuplicate else {
            return nil
        }

        return duplicateItem.purchased ? .pickedUp(duplicateItem) : .alreadyNeeded(duplicateItem)
    }

    private var localDuplicate: ShoppingListItem? {
        let normalizedName = duplicateLookupKey

        guard !normalizedName.isEmpty else {
            return nil
        }

        return viewModel.items.first { item in
            item.id != mode.editingItemID
                && normalizedShoppingItemName(item.name) == normalizedName
        }
    }

    private var filteredServerDuplicate: ShoppingListItem? {
        guard serverDuplicate?.id != mode.editingItemID else {
            return nil
        }

        return serverDuplicate
    }

    private func updateServerDuplicate(for lookupKey: String) async {
        serverDuplicate = nil
        didFailDuplicateLookup = false

        guard !lookupKey.isEmpty else {
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }

        guard !Task.isCancelled else {
            return
        }

        isCheckingDuplicate = true

        defer {
            isCheckingDuplicate = false
        }

        do {
            let match = try await viewModel.lookupDuplicate(named: draft.trimmedName)

            guard !Task.isCancelled else {
                return
            }

            serverDuplicate = match
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            didFailDuplicateLookup = true
        }
    }

    private func submit() async {
        guard !isPrimaryDisabled else {
            return
        }

        isSubmitting = true
        formErrorMessage = nil

        defer {
            isSubmitting = false
        }

        do {
            switch mode {
            case .add:
                try await viewModel.createItem(from: draft)
            case .edit(let item):
                try await viewModel.updateItem(id: item.id, with: draft)
            }

            dismiss()
        } catch {
            formErrorMessage = error.localizedDescription
        }
    }

    private func addBackToNeeded(_ item: ShoppingListItem) async {
        guard !isAddingBack, !viewModel.isMutatingItem(item.id) else {
            return
        }

        isAddingBack = true
        formErrorMessage = nil

        defer {
            isAddingBack = false
        }

        do {
            try await viewModel.addBackToNeeded(item, from: draft)
            dismiss()
        } catch {
            formErrorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: ShoppingListItem) async {
        guard !viewModel.isMutatingItem(item.id) else {
            pendingDeleteItem = nil
            return
        }

        defer {
            pendingDeleteItem = nil
        }

        do {
            try await viewModel.deleteItem(item)
            dismiss()
        } catch {
            formErrorMessage = error.localizedDescription
        }
    }

    private func toggleStore(_ store: ShoppingStore) {
        if draft.selectedStoreIds.contains(store.id) {
            draft.selectedStoreIds.remove(store.id)
        } else {
            draft.selectedStoreIds.insert(store.id)
        }
    }
}

private struct ShoppingFormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(.headline)

            content
        }
    }
}

private struct ShoppingChoiceChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 42)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? AppColors.accent : Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ShoppingCategorySection: View {
    let group: ShoppingCategoryGroup
    let mutatingItemIDs: Set<Int>
    let onTogglePurchased: (ShoppingListItem) -> Void
    let onAdjustQuantity: (ShoppingListItem, Int) -> Void
    let onEdit: (ShoppingListItem) -> Void
    let onDelete: (ShoppingListItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: group.category.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(group.category.tone.foregroundColor)
                    .frame(width: 30, height: 30)
                    .background(group.category.tone.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))

                Text(group.category.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(group.items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)

            Divider()
                .padding(.leading, AppSpacing.large)

            ForEach(group.items) { item in
                ShoppingItemRow(
                    displayItem: item,
                    isMutating: mutatingItemIDs.contains(item.item.id),
                    onTogglePurchased: {
                        onTogglePurchased(item.item)
                    },
                    onIncrementQuantity: {
                        onAdjustQuantity(item.item, 1)
                    },
                    onDecrementQuantity: {
                        onAdjustQuantity(item.item, -1)
                    },
                    onEdit: {
                        onEdit(item.item)
                    },
                    onDelete: {
                        onDelete(item.item)
                    }
                )

                if item.id != group.items.last?.id {
                    Divider()
                        .padding(.leading, 58)
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

private struct ShoppingItemRow: View {
    let displayItem: ShoppingListDisplayItem
    let isMutating: Bool
    let onTogglePurchased: () -> Void
    let onIncrementQuantity: () -> Void
    let onDecrementQuantity: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Button(action: onTogglePurchased) {
                Image(systemName: displayItem.item.purchased ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(displayItem.item.purchased ? AppColors.success : AppColors.accent)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(isMutating)
            .accessibilityLabel(displayItem.item.purchased ? "Mark needed" : "Mark picked up")

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(displayItem.item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(displayItem.item.purchased ? AppColors.mutedText : .primary)
                    .strikethrough(displayItem.item.purchased, color: AppColors.mutedText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                if let detailText = displayItem.detailText {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !displayItem.stores.isEmpty {
                    HStack(spacing: AppSpacing.xSmall) {
                        ForEach(displayItem.stores) { store in
                            Text(store.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, AppSpacing.small)
                                .frame(height: 24)
                                .foregroundStyle(AppColors.accent)
                                .background(AppColors.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
                        }
                    }
                }
            }

            Spacer(minLength: AppSpacing.small)

            VStack(alignment: .trailing, spacing: AppSpacing.small) {
                RowQuantityStepper(
                    quantity: displayItem.item.quantity,
                    isDisabled: isMutating,
                    onDecrement: onDecrementQuantity,
                    onIncrement: onIncrementQuantity
                )

                if isMutating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.mutedText)
                }
            }
        }
        .padding(AppSpacing.medium)
        .opacity(displayItem.item.purchased ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayItem.accessibilityLabel)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppColors.accent)
        }
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

private struct RowQuantityStepper: View {
    let quantity: Int
    let isDisabled: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 28)
            }
            .disabled(isDisabled || quantity <= 1)

            Text("Qty \(quantity)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 48)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 28)
            }
            .disabled(isDisabled)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? AppColors.mutedText : AppColors.accent)
        .padding(.horizontal, AppSpacing.xSmall)
        .frame(height: 32)
        .background(AppColors.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ShoppingCategoryGroup: Identifiable {
    let category: ShoppingCategory
    let items: [ShoppingListDisplayItem]

    var id: ShoppingCategory { category }
}

private struct ShoppingListDisplayItem: Identifiable, Comparable {
    let item: ShoppingListItem
    let category: ShoppingCategory
    let stores: [ShoppingStore]

    var id: Int { item.id }

    var detailText: String? {
        var details: [String] = []

        if let brand = item.brand {
            details.append(brand)
        }

        if let notes = item.notes {
            details.append(notes)
        }

        return details.isEmpty ? nil : details.joined(separator: " - ")
    }

    var accessibilityLabel: String {
        let state = item.purchased ? "picked up" : "needed"
        let storeNames = stores.map(\.name).joined(separator: ", ")
        let storesText = storeNames.isEmpty ? "" : ", stores \(storeNames)"

        return "\(item.name), quantity \(item.quantity), \(category.name), \(state)\(storesText)"
    }

    func matches(_ searchText: String) -> Bool {
        let searchableValues = [
            item.name,
            item.brand,
            item.notes,
            category.name,
        ] + stores.map(\.name)

        return searchableValues
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    static func < (lhs: ShoppingListDisplayItem, rhs: ShoppingListDisplayItem) -> Bool {
        if lhs.item.purchased != rhs.item.purchased {
            return !lhs.item.purchased && rhs.item.purchased
        }

        return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
    }
}

private extension ShoppingCategory {
    var systemImage: String {
        let normalizedName = name.lowercased()

        if normalizedName.contains("produce")
            || normalizedName.contains("fruit")
            || normalizedName.contains("vegetable") {
            return "carrot"
        }

        if normalizedName.contains("dairy") {
            return "drop"
        }

        if normalizedName.contains("meat")
            || normalizedName.contains("seafood") {
            return "fork.knife"
        }

        if normalizedName.contains("frozen") {
            return "snowflake"
        }

        if normalizedName.contains("pantry")
            || normalizedName.contains("dry")
            || normalizedName.contains("canned") {
            return "cabinet"
        }

        if normalizedName.contains("home")
            || normalizedName.contains("household") {
            return "house"
        }

        return "cart"
    }

    var tone: StatusBadgeTone {
        let normalizedName = name.lowercased()

        if normalizedName.contains("produce")
            || normalizedName.contains("fruit")
            || normalizedName.contains("vegetable") {
            return .success
        }

        if normalizedName.contains("dairy")
            || normalizedName.contains("frozen") {
            return .accent
        }

        return .neutral
    }
}

#Preview("Loaded") {
    NavigationStack {
        ShoppingListContentView(
            viewModel: ShoppingListViewModel(loadShoppingList: {
                ShoppingListResponse(
                    ok: true,
                    items: [
                        ShoppingListItem(
                            id: 1,
                            name: "Whole milk",
                            brand: "Horizon",
                            quantity: 2,
                            notes: "Half gallon",
                            purchased: false,
                            createdAt: "2026-06-22T12:00:00.000Z",
                            updatedAt: "2026-06-22T12:30:00.000Z",
                            storeIds: [1],
                            categoryId: 2
                        )
                    ],
                    stores: [
                        ShoppingStore(id: 1, name: "Target", logo: "target")
                    ],
                    categories: [
                        ShoppingCategory(id: 2, name: "Dairy")
                    ],
                    generatedAt: "2026-06-22T12:31:00.000Z"
                )
            })
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        ShoppingListContentView(
            viewModel: ShoppingListViewModel(loadShoppingList: {
                ShoppingListResponse(
                    ok: true,
                    items: [],
                    stores: [],
                    categories: [],
                    generatedAt: "2026-06-22T12:31:00.000Z"
                )
            })
        )
    }
}
