import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShoppingListMockupView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        let viewerIdentity = ShoppingListViewerIdentity.defaultDevice()

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
    }
}

private extension ShoppingListViewerIdentity {
    static func defaultDevice(userDefaults: UserDefaults = .standard) -> ShoppingListViewerIdentity {
        let deviceName = currentDeviceName

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

@MainActor
final class ShoppingListViewModel: ObservableObject {
    typealias ShoppingListLoader = () async throws -> ShoppingListResponse

    @Published private(set) var items: [ShoppingListItem] = []
    @Published private(set) var stores: [ShoppingStore] = []
    @Published private(set) var categories: [ShoppingCategory] = []
    @Published private(set) var activeViewers: [ShoppingListViewerPresence] = []
    @Published private(set) var generatedAt: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false

    private let loadShoppingList: ShoppingListLoader
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
            currentViewerId == nil || viewer.viewerId != currentViewerId
        }
    }

    var otherActiveViewerLabel: String? {
        let names = otherActiveViewers
            .map(\.displayName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !names.isEmpty else {
            return nil
        }

        if names.count == 1 {
            let name = names[0]
            return name.count <= 12 ? "\(name) viewing" : "Someone viewing"
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
            currentViewerId: currentViewerId
        ) {
            try await apiClient.fetchShoppingList()
        }
    }

    init(
        liveService: ShoppingListLiveServicing? = nil,
        currentViewerId: String? = nil,
        loadShoppingList: @escaping ShoppingListLoader
    ) {
        self.loadShoppingList = loadShoppingList
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

    private static func deduplicatedViewers(
        _ viewers: [ShoppingListViewerPresence]
    ) -> [ShoppingListViewerPresence] {
        var viewersById: [String: ShoppingListViewerPresence] = [:]

        for viewer in viewers {
            if let existingViewer = viewersById[viewer.viewerId],
               existingViewer.lastSeenAt >= viewer.lastSeenAt {
                continue
            }

            viewersById[viewer.viewerId] = viewer
        }

        return viewersById.values.sorted { first, second in
            first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
        }
    }
}

private struct ShoppingListContentView: View {
    @StateObject private var viewModel: ShoppingListViewModel
    @State private var searchText = ""
    @State private var selectedCategoryId: Int?

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
                ShoppingCategorySection(group: group)
            }
        }
    }

    private var summaryPanel: some View {
        InfoPanel(
            title: "Grocery List",
            subtitle: "\(neededItemCount) \(neededItemCount == 1 ? "item" : "items") needed",
            systemImage: "cart"
        ) {
            HStack(spacing: AppSpacing.medium) {
                StatusBadgeView(label: "Database", systemImage: "externaldrive.connected.to.line.below", tone: .accent)
                StatusBadgeView(label: "\(completedItemCount) picked up", systemImage: "checkmark.circle", tone: .success)

                if let otherActiveViewerLabel = viewModel.otherActiveViewerLabel {
                    StatusBadgeView(label: otherActiveViewerLabel, systemImage: "person.2", tone: .neutral)
                }

                Spacer(minLength: 0)
            }
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
                    .foregroundStyle(isSelected ? .white.opacity(0.86) : AppColors.mutedText)
            }
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 36)
            .foregroundStyle(isSelected ? .white : AppColors.accent)
            .background(isSelected ? AppColors.accent : AppColors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ShoppingCategorySection: View {
    let group: ShoppingCategoryGroup

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
                ShoppingItemRow(displayItem: item)

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

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: displayItem.item.purchased ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(displayItem.item.purchased ? AppColors.success : AppColors.mutedText)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

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

            QuantityBadge(quantity: displayItem.item.quantity)
        }
        .padding(AppSpacing.medium)
        .opacity(displayItem.item.purchased ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayItem.accessibilityLabel)
    }
}

private struct QuantityBadge: View {
    let quantity: Int

    var body: some View {
        Text("Qty \(quantity)")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.small)
            .frame(height: 32)
            .foregroundStyle(AppColors.accent)
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
