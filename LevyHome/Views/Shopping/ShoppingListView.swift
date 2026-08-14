import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShoppingListView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @AppStorage(ResidentPreference.storageKey, store: ResidentPreference.sharedDefaults)
    private var currentResidentName = ResidentDeviceOwnerDefaults.defaultName
    let isSelected: Bool

    init(isSelected: Bool = true) {
        self.isSelected = isSelected
    }

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
                appLogStore: appEnvironment.appLogStore,
                currentViewerId: viewerIdentity.viewerId,
                currentActorName: viewerIdentity.displayName
            ),
            isSelected: isSelected
        )
        .id(viewerIdentity.viewerId)
    }
}

private extension ShoppingListViewerIdentity {
    static func forResidentPreference(_ residentName: String) -> ShoppingListViewerIdentity {
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

        let fallbackResident = ResidentIdentity.josh
        return ShoppingListViewerIdentity(
            viewerId: fallbackResident.shoppingListViewerId,
            displayName: fallbackResident.rawValue,
            deviceName: deviceName
        )
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

struct ShoppingItemDraft: Equatable {
    var name: String
    var brand: String
    var quantity: Int
    var notes: String
    var selectedCategoryId: Int?
    var image: String
    var storeListings: [ShoppingItemStoreListing]
    var purchased: Bool

    init(
        name: String = "",
        brand: String = "",
        quantity: Int = 1,
        notes: String = "",
        selectedCategoryId: Int? = nil,
        image: String = "",
        storeListings: [ShoppingItemStoreListing] = [],
        purchased: Bool = false
    ) {
        self.name = name
        self.brand = brand
        self.quantity = max(1, quantity)
        self.notes = notes
        self.selectedCategoryId = selectedCategoryId
        self.image = image
        self.storeListings = storeListings
        self.purchased = purchased
    }

    init(item: ShoppingListItem, defaultCategoryId: Int? = nil) {
        self.init(
            name: item.name,
            brand: item.brand ?? "",
            quantity: item.quantity,
            notes: item.notes ?? "",
            selectedCategoryId: item.categoryId ?? defaultCategoryId,
            image: item.image ?? "",
            storeListings: item.storeListings,
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

    func createRequest(actor: String? = nil) -> CreateShoppingListItemRequest {
        CreateShoppingListItemRequest(
            name: trimmedName,
            brand: normalizedOptionalText(brand),
            quantity: quantity,
            notes: normalizedOptionalText(notes),
            purchased: purchased,
            categoryId: selectedCategoryId,
            image: normalizedOptionalText(image),
            storeListings: storeListings,
            actor: actor
        )
    }

    func updateRequest(
        comparedTo item: ShoppingListItem,
        actor: String? = nil
    ) -> UpdateShoppingListItemRequest {
        let normalizedBrand = normalizedOptionalText(brand)
        let normalizedNotes = normalizedOptionalText(notes)
        let normalizedImage = normalizedOptionalText(image)

        return UpdateShoppingListItemRequest(
            name: trimmedName == item.name ? nil : trimmedName,
            brand: normalizedBrand == item.brand ? nil : nullableString(brand),
            quantity: quantity == item.quantity ? nil : quantity,
            notes: normalizedNotes == item.notes ? nil : nullableString(notes),
            categoryId: selectedCategoryId == item.categoryId ? nil : nullableCategoryId,
            image: normalizedImage == item.image ? nil : nullableString(image),
            storeListings: storeListings == item.storeListings ? nil : storeListings,
            actor: actor
        )
    }

    func addBackRequest(actor: String? = nil) -> UpdateShoppingListItemRequest {
        UpdateShoppingListItemRequest(
            quantity: quantity,
            notes: optionalNullableString(notes),
            purchased: false,
            categoryId: selectedCategoryId.map { .value($0) },
            image: optionalNullableString(image),
            storeListings: storeListings.isEmpty ? nil : storeListings,
            actor: actor
        )
    }

    var selectedStoreIds: Set<Int> {
        Set(storeListings.compactMap(\.storeId))
    }

    var selectedKrogerProductName: String? {
        storeListings.first { listing in
            listing.krogerLocationId != nil || listing.product?.productId != nil
        }?.product?.name
    }

    mutating func toggleStore(_ store: ShoppingStore) {
        if selectedStoreIds.contains(store.id) {
            storeListings.removeAll { $0.storeId == store.id }
        } else {
            storeListings.append(Self.manualListing(for: store))
        }
    }

    func listing(for store: ShoppingStore) -> ShoppingItemStoreListing? {
        storeListings.first { listing in
            if let storeId = listing.storeId {
                return storeId == store.id
            }

            return listing.storeName?.localizedCaseInsensitiveCompare(store.name) == .orderedSame
        }
    }

    func manualAisleNumber(for store: ShoppingStore) -> String {
        listing(for: store)?.aisle?.number ?? ""
    }

    func manualShelfNumber(for store: ShoppingStore) -> String {
        listing(for: store)?.aisle?.shelfNumber ?? ""
    }

    func manualPriceText(for store: ShoppingStore) -> String {
        guard let unitPrice = listing(for: store)?.price?.estimatedUnitPrice else {
            return ""
        }

        return unitPrice.formatted(.number.precision(.fractionLength(0...2)))
    }

    var manualPriceTextByStoreId: [Int: String] {
        storeListings.reduce(into: [Int: String]()) { priceTextByStoreId, listing in
            guard let storeId = listing.storeId,
                  let unitPrice = listing.price?.estimatedUnitPrice else {
                return
            }

            priceTextByStoreId[storeId] = unitPrice.formatted(.number.precision(.fractionLength(0...2)))
        }
    }

    mutating func updateManualAisleNumber(_ aisleNumber: String, for store: ShoppingStore) {
        updateManualListing(for: store, aisleNumber: aisleNumber)
    }

    mutating func updateManualShelfNumber(_ shelfNumber: String, for store: ShoppingStore) {
        updateManualListing(for: store, shelfNumber: shelfNumber)
    }

    mutating func updateManualPriceText(_ priceText: String, for store: ShoppingStore) {
        updateManualListing(for: store, priceText: priceText)
    }

    mutating func apply(product: KrogerProduct, kingSoopersStore: ShoppingStore?) {
        if let brand = product.brand, !brand.isEmpty {
            self.brand = brand
        }

        if normalizedOptionalText(image) == nil,
           let productImage = product.image.flatMap({ normalizedOptionalText($0) }) {
            image = productImage
        }

        var listing = product.storeListings.first ?? Self.krogerListing(from: product, store: kingSoopersStore)
        listing = listing.withStoreFallback(kingSoopersStore)
        storeListings.removeAll { existing in
            if let storeId = listing.storeId {
                return existing.storeId == storeId
            }

            return existing.krogerLocationId != nil || existing.product?.productId != nil
        }
        storeListings.append(listing)
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

    private static func manualListing(for store: ShoppingStore) -> ShoppingItemStoreListing {
        ShoppingItemStoreListing(
            storeId: store.id,
            storeName: store.name,
            source: "manual",
            availability: ShoppingStoreListingAvailability(status: "unknown", checkedAt: nil)
        )
    }

    private mutating func updateManualListing(
        for store: ShoppingStore,
        aisleNumber: String? = nil,
        shelfNumber: String? = nil,
        priceText: String? = nil
    ) {
        let existingListing = listing(for: store) ?? Self.manualListing(for: store)
        let updatedAisleNumber = aisleNumber ?? existingListing.aisle?.number ?? ""
        let updatedShelfNumber = shelfNumber ?? existingListing.aisle?.shelfNumber ?? ""
        let updatedPriceText = priceText ?? manualPriceText(for: store)
        let updatedListing = ShoppingItemStoreListing(
            storeId: existingListing.storeId ?? store.id,
            storeName: existingListing.storeName ?? store.name,
            source: existingListing.source ?? "manual",
            krogerLocationId: existingListing.krogerLocationId,
            product: existingListing.product,
            aisle: Self.manualAisle(
                aisleNumber: updatedAisleNumber,
                shelfNumber: updatedShelfNumber
            ),
            price: Self.manualPrice(from: updatedPriceText),
            inventory: existingListing.inventory,
            fulfillment: existingListing.fulfillment,
            availability: existingListing.availability ?? ShoppingStoreListingAvailability(status: "unknown", checkedAt: nil),
            checkedAt: existingListing.checkedAt
        )

        storeListings.removeAll { listing in
            if let storeId = listing.storeId {
                return storeId == store.id
            }

            return listing.storeName?.localizedCaseInsensitiveCompare(store.name) == .orderedSame
        }
        storeListings.append(updatedListing)
    }

    private static func manualAisle(
        aisleNumber: String,
        shelfNumber: String
    ) -> ShoppingStoreListingAisle? {
        let normalizedAisleNumber = normalizedOptionalText(aisleNumber)
        let normalizedShelfNumber = normalizedOptionalText(shelfNumber)
        let display = [normalizedAisleNumber, normalizedShelfNumber]
            .compactMap { $0 }
            .joined(separator: ":")
            .nilIfEmpty

        guard display != nil || normalizedAisleNumber != nil || normalizedShelfNumber != nil else {
            return nil
        }

        return ShoppingStoreListingAisle(
            display: display,
            description: normalizedAisleNumber.map { "AISLE \($0)" },
            number: normalizedAisleNumber,
            shelfNumber: normalizedShelfNumber,
            raw: nil
        )
    }

    private static func manualPrice(from priceText: String) -> ShoppingStoreListingPrice? {
        let normalizedPriceText = priceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard !normalizedPriceText.isEmpty, let price = Double(normalizedPriceText), price >= 0 else {
            return nil
        }

        return ShoppingStoreListingPrice(regular: price, promo: nil)
    }

    private static func normalizedOptionalText(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func krogerListing(from product: KrogerProduct, store: ShoppingStore?) -> ShoppingItemStoreListing {
        ShoppingItemStoreListing(
            storeId: store?.id ?? 2,
            storeName: store?.name ?? "King Soopers",
            krogerLocationId: "62000008",
            product: ShoppingStoreListingProduct(
                productId: product.productId,
                upc: product.upc,
                productPageURI: product.productPageURI,
                brand: product.brand,
                name: product.name,
                description: product.description,
                image: product.image
            ),
            aisle: product.aisles.first.map { aisle in
                ShoppingStoreListingAisle(
                    display: [aisle.number, aisle.shelfNumber].compactMap { $0 }.joined(separator: ":").nilIfEmpty,
                    description: aisle.description,
                    number: aisle.number,
                    shelfNumber: aisle.shelfNumber,
                    raw: aisle.rawJSON
                )
            }
        )
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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var pushRegistrationViewModel: PushRegistrationViewModel
    @EnvironmentObject private var shoppingLiveActivityCoordinator: ShoppingLiveActivityCoordinator
    @StateObject private var viewModel: ShoppingListViewModel
    @State private var searchText = ""
    @State private var selectedCategoryId: Int?
    @State private var appliedFilters = ShoppingListFilters()
    @State private var draftFilters = ShoppingListFilters()
    @State private var isShowingFilterSheet = false
    @State private var editorMode: ShoppingItemEditorMode?
    @State private var pendingDeleteItem: ShoppingListItem?
    @State private var tripDisplayMessage: String?
    @State private var isShowingEndTripConfirmation = false
    @State private var isShowingStockPriceCheckSummary = false
    @State private var isShowingShoppingListReaddSheet = false
    let isSelected: Bool

    init(viewModel: ShoppingListViewModel, isSelected: Bool = true) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.isSelected = isSelected
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                AppScreenHeader(title: "Shopping") {
                    AppHeaderIconButton(
                        systemImage: "plus",
                        accessibilityLabel: "Add shopping item"
                    ) {
                        editorMode = .add
                    }
                }

                if viewModel.isLoading {
                    loadingView
                } else {
                    contentView
                }
            }
            .padding(.horizontal, AppSpacing.screen)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, AppSpacing.xLarge * 4)
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            ShoppingAIFloatingEntry(
                status: shoppingAIStatus,
                isUnavailable: false,
                action: {
                    isShowingShoppingListReaddSheet = true
                }
            )
            .padding(.horizontal, AppSpacing.screen)
            .padding(.top, AppSpacing.small)
            .padding(.bottom, AppSpacing.small)
        }
        .appScreenChrome()
        .task {
            guard isSelected, scenePhase == .active else {
                return
            }

            await viewModel.loadIfNeeded()
            await recoverActiveTripDisplay()
            viewModel.setStockPriceCheckPollingAllowed(true)
            viewModel.setShoppingListReaddPollingAllowed(true)
        }
        .onChange(of: isSelected) { _, selected in
            guard selected else {
                viewModel.stopLiveUpdates()
                viewModel.setStockPriceCheckPollingAllowed(false)
                viewModel.setShoppingListReaddPollingAllowed(false)
                return
            }
            Task { await refreshForSelectedVisit() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isSelected else {
                viewModel.stopLiveUpdates()
                viewModel.setStockPriceCheckPollingAllowed(false)
                viewModel.setShoppingListReaddPollingAllowed(false)
                return
            }
            Task { await refreshForSelectedVisit() }
        }
        .onDisappear {
            viewModel.stopLiveUpdates()
            viewModel.setStockPriceCheckPollingAllowed(false)
            viewModel.setShoppingListReaddPollingAllowed(false)
        }
        .onChange(of: viewModel.activeTrip?.id) { _, _ in
            guard isSelected else { return }
            Task { await recoverActiveTripDisplay() }
        }
        .onChange(of: viewModel.activeTrip?.version) { _, _ in
            guard let trip = viewModel.activeTrip, isSelected else { return }
            Task { await shoppingLiveActivityCoordinator.updateTripActivity(for: trip) }
        }
        .onChange(of: viewModel.finalStockPriceCheckSummary?.id) { _, jobID in
            isShowingStockPriceCheckSummary = jobID != nil
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $editorMode) { mode in
            ShoppingItemEditorSheet(
                mode: mode,
                viewModel: viewModel
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            ShoppingListFilterSheet(
                filters: $draftFilters,
                onClear: {
                    appliedFilters = ShoppingListFilters()
                    draftFilters = ShoppingListFilters()
                    isShowingFilterSheet = false
                },
                onApply: {
                    if draftFilters.viewMode == .compact {
                        selectedCategoryId = nil
                    }
                    appliedFilters = draftFilters
                    isShowingFilterSheet = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingStockPriceCheckSummary, onDismiss: {
            viewModel.dismissFinalStockPriceCheckSummary()
        }) {
            if let summary = viewModel.finalStockPriceCheckSummary {
                ShoppingStockPriceCheckSummarySheet(summary: summary) {
                    isShowingStockPriceCheckSummary = false
                    viewModel.dismissFinalStockPriceCheckSummary()
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isShowingShoppingListReaddSheet) {
            ShoppingListReaddSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "End Shopping Trip?",
            isPresented: $isShowingEndTripConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Shop", role: .destructive) {
                Task { await endTrip() }
            }
            Button("Keep Shopping", role: .cancel) {}
        } message: {
            if let trip = viewModel.activeTrip {
                Text(endTripConfirmationMessage(for: trip))
            }
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

        if let tripDisplayMessage {
            InfoPanel(
                title: "Shopping Trip Display",
                subtitle: tripDisplayMessage,
                systemImage: "lock.rectangle"
            ) {}
        }

        ShoppingListSearchField(searchText: $searchText)

        if appliedFilters.viewMode == .detailed {
            ShoppingCategoryFilterBar(
                selectedCategoryId: $selectedCategoryId,
                categories: filterCategories,
                counts: categoryCounts
            )
        }

        if viewModel.isEmpty || filteredItems.isEmpty {
            emptyState
        } else {
            switch appliedFilters.viewMode {
            case .detailed:
                ForEach(groupedItems) { group in
                    ShoppingCategorySection(
                        group: group,
                        mutatingItemIDs: viewModel.mutatingItemIDs,
                        onTogglePurchased: togglePurchased,
                        onEdit: { item in
                            editorMode = .edit(item)
                        },
                        onDelete: { item in
                            pendingDeleteItem = item
                        }
                    )
                }
            case .compact:
                if !compactNeededItems.isEmpty {
                    ShoppingCompactSection(
                        title: "Needed",
                        systemImage: "cart.badge.plus",
                        items: compactNeededItems,
                        mutatingItemIDs: viewModel.mutatingItemIDs,
                        onTogglePurchased: togglePurchased,
                        onEdit: { item in
                            editorMode = .edit(item)
                        },
                        onDelete: { item in
                            pendingDeleteItem = item
                        }
                    )
                }

                if !compactPickedUpItems.isEmpty {
                    ShoppingCompactSection(
                        title: "Picked Up",
                        systemImage: "checkmark.circle.fill",
                        items: compactPickedUpItems,
                        mutatingItemIDs: viewModel.mutatingItemIDs,
                        onTogglePurchased: togglePurchased,
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
    }

    private var summaryPanel: some View {
        ShoppingListSummaryCard(
            residentAvatars: viewModel.residentAvatarStates,
            activeTrip: viewModel.activeTrip,
            remainingText: activeTripRemainingText,
            estimatedTotalText: activeTripEstimatedTotalText,
            isFilterActive: appliedFilters.isActive,
            isTripActionInFlight: viewModel.isStartingTrip || viewModel.isEndingTrip,
            onStartShop: {
                Task { await startTrip() }
            },
            onEndShop: {
                isShowingEndTripConfirmation = true
            },
            onFilter: {
                draftFilters = appliedFilters
                isShowingFilterSheet = true
            }
        )
        .animation(.easeInOut(duration: 0.16), value: viewModel.residentAvatarStates)
    }

    private var activeTripRemainingText: String {
        if let trip = viewModel.activeTrip {
            return "\(trip.pickedUpCount) picked up • \(trip.remainingCount) left"
        }

        return "\(neededItemCount) left of \(totalItemCount)"
    }

    private var activeTripEstimatedTotalText: String {
        guard let trip = viewModel.activeTrip else {
            return estimatedRemainingTotalText
        }

        let amount = Decimal(trip.estimatedTotalCents) / 100
        let estimate = amount.formatted(.currency(code: trip.currencyCode))
        return "Picked-up est. \(estimate) • Started by \(trip.startedBy)"
    }

    private var shoppingAIStatus: ShoppingAIStatus? {
        if viewModel.isStartingShoppingListReadd {
            return ShoppingAIStatus(
                message: "Finding shopping items…",
                systemImage: "sparkles",
                tone: .info
            )
        }

        if viewModel.isShoppingListReaddActive {
            return ShoppingAIStatus(
                message: "Finding shopping items…",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info
            )
        }

        if viewModel.isStartingStockPriceCheck {
            return ShoppingAIStatus(
                message: "Starting stock & price check…",
                systemImage: "sparkles",
                tone: .info
            )
        }

        if let errorMessage = viewModel.stockPriceCheckErrorMessage {
            return ShoppingAIStatus(
                message: "Stock & price check paused: \(errorMessage)",
                systemImage: "exclamationmark.triangle",
                tone: .warning
            )
        }

        if viewModel.isStockPriceCheckActive {
            let progress = viewModel.stockPriceCheckProgressLabel.map { " \($0)" } ?? ""
            return ShoppingAIStatus(
                message: "Checking stock & price…\(progress)",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .info
            )
        }

        guard let summary = viewModel.finalStockPriceCheckSummary else {
            return nil
        }

        switch summary.status {
        case .completedWithIssues:
            return ShoppingAIStatus(
                message: "Stock & price check finished. Some items need review.",
                systemImage: "exclamationmark.circle",
                tone: .warning
            )
        case .failed:
            return ShoppingAIStatus(
                message: summary.message ?? "Stock & price check did not finish.",
                systemImage: "xmark.octagon",
                tone: .error
            )
        case .completed, .queued, .running, .unknown:
            return nil
        }
    }

    private func startTrip() async {
        guard let response = await viewModel.startTrip(
            originatingPushDeviceId: pushRegistrationViewModel.registeredDeviceID
        ) else {
            return
        }

        guard response.displayDisposition?.startsLocally == true else {
            tripDisplayMessage = "The shared trip is active. This iPhone is waiting for its already-persisted remote Live Activity start."
            return
        }

        let result = await shoppingLiveActivityCoordinator.startTripActivity(for: response.trip)
        tripDisplayMessage = result.message

        if response.displayDisposition?.remoteStartCount == 0 {
            tripDisplayMessage = "\(result.message) No counterpart Live Activity could be queued because no current ActivityKit start token is registered."
        }
    }

    private func endTrip() async {
        guard let response = await viewModel.endTrip() else { return }
        let result = await shoppingLiveActivityCoordinator.endTripActivity(for: response.trip)
        tripDisplayMessage = result.message
    }

    private func endTripConfirmationMessage(for trip: ShoppingTrip) -> String {
        let estimate = trip.pricedPickedItemCount > 0
            ? " Estimated \\((Decimal(trip.estimatedTotalCents) / 100).formatted(.currency(code: trip.currencyCode)))."
            : ""
        return "\\(trip.pickedUpCount) picked up • \\(trip.remainingCount) left.\\(estimate)"
    }

    private func refreshForSelectedVisit() async {
        viewModel.setStockPriceCheckPollingAllowed(true)
        viewModel.setShoppingListReaddPollingAllowed(true)
        await viewModel.refresh()
        await recoverActiveTripDisplay()
    }

    private func recoverActiveTripDisplay() async {
        guard let trip = viewModel.activeTrip else {
            await shoppingLiveActivityCoordinator.retireOrphanedTripActivities(keepingTripID: nil)
            return
        }
        await shoppingLiveActivityCoordinator.retireOrphanedTripActivities(keepingTripID: trip.id)
        guard let disposition = await viewModel.claimActiveTripDisplay(
            pushDeviceId: pushRegistrationViewModel.registeredDeviceID
        ) else { return }

        guard disposition.startsLocally else {
            tripDisplayMessage = "The shared trip is active. This iPhone is waiting for its remote Live Activity start."
            return
        }

        let recovered = await shoppingLiveActivityCoordinator.recoverTripActivity(for: trip)
        if recovered.shouldStartReplacement {
            let started = await shoppingLiveActivityCoordinator.startTripActivity(for: trip)
            tripDisplayMessage = started.message
        } else {
            tripDisplayMessage = recovered.message
        }
    }

    private var loadingView: some View {
        InfoPanel(
            title: "Loading Shopping List",
            subtitle: "Fetching items from the database.",
            systemImage: "cart"
        ) {
            InlineLoadingView(message: "Checking the shared list...")
        }
    }

    private var emptyState: some View {
        InfoPanel(
            title: viewModel.items.isEmpty ? "No Shopping Items" : "No Matching Items",
            subtitle: viewModel.items.isEmpty ? "The database list is empty." : "Try a product name, store, or category.",
            systemImage: viewModel.items.isEmpty ? "cart" : "magnifyingglass"
        ) {
            if !searchText.isEmpty || selectedCategoryId != nil || appliedFilters.isActive {
                Button {
                    searchText = ""
                    selectedCategoryId = nil
                    appliedFilters = ShoppingListFilters()
                    draftFilters = ShoppingListFilters()
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

    private var compactNeededItems: [ShoppingListDisplayItem] {
        compactItems(purchased: false)
    }

    private var compactPickedUpItems: [ShoppingListDisplayItem] {
        compactItems(purchased: true)
    }

    private func compactItems(purchased: Bool) -> [ShoppingListDisplayItem] {
        filteredItems
            .filter { $0.item.purchased == purchased }
            .sorted(by: ShoppingListDisplayItem.isMoreRecentlyActive)
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
            .filter { displayItem in
                appliedFilters.matches(displayItem, storesById: storesById)
            }
    }

    private var displayItems: [ShoppingListDisplayItem] {
        let categoriesById = Dictionary(uniqueKeysWithValues: viewModel.categories.map { ($0.id, $0) })

        return viewModel.items.map { item in
            ShoppingListDisplayItem(
                item: item,
                category: category(for: item, categoriesById: categoriesById)
            )
        }
    }

    private var storesById: [Int: ShoppingStore] {
        Dictionary(uniqueKeysWithValues: viewModel.stores.map { ($0.id, $0) })
    }

    private var filterCategories: [ShoppingCategory] {
        let responseCategories = viewModel.categories
        let categoriesById = Dictionary(uniqueKeysWithValues: responseCategories.map { ($0.id, $0) })
        let missingCategories = Set(viewModel.items.compactMap(\.categoryId))
            .filter { categoriesById[$0] == nil }
            .map { ShoppingCategory(id: $0, name: "Category \($0)") }
        let allCategories = responseCategories
            + missingCategories
            + (viewModel.items.contains { $0.categoryId == nil } && defaultCategory == nil ? [Self.fallbackMiscellaneousCategory] : [])

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

    private var totalItemCount: Int {
        viewModel.items.count
    }

    private var estimatedRemainingTotalText: String {
        let total = viewModel.items
            .filter { !$0.purchased }
            .reduce(0.0) { partialTotal, item in
                guard let unitPrice = ShoppingStoreListingPresentation
                    .coalescedListings(from: item.storeListings)
                    .compactMap(\.estimatedUnitPrice)
                    .max() else {
                    return partialTotal
                }

                return partialTotal + (unitPrice * Double(max(1, item.quantity)))
            }

        guard total > 0 else {
            return "Est. --"
        }

        return "Est. \(total.formatted(.currency(code: "USD")))"
    }

    private func category(
        for item: ShoppingListItem,
        categoriesById: [Int: ShoppingCategory]
    ) -> ShoppingCategory {
        guard let categoryId = item.categoryId else {
            return defaultCategory ?? Self.fallbackMiscellaneousCategory
        }

        return categoriesById[categoryId] ?? ShoppingCategory(id: categoryId, name: "Category \(categoryId)")
    }

    private var defaultCategory: ShoppingCategory? {
        viewModel.miscellaneousCategory ?? viewModel.categories.first
    }

    private static let fallbackMiscellaneousCategory = ShoppingCategory(id: 0, name: "Miscellaneous")

    private func togglePurchased(_ item: ShoppingListItem) {
        Task {
            if let trip = await viewModel.setPurchased(item, purchased: !item.purchased) {
                await shoppingLiveActivityCoordinator.updateTripActivity(for: trip)
            }
        }
    }

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

private struct ShoppingAIStatus: Equatable {
    let message: String
    let systemImage: String
    let tone: BannerTone
}

private struct ShoppingListReaddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ShoppingListViewModel
    @FocusState private var isRequestTextFocused: Bool
    @State private var requestText = ""
    @State private var textBeforeVoiceInput = ""
    @StateObject private var speechTranscription = ShoppingSpeechTranscriptionService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                header

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("What do you need?")
                        .font(.headline)

                    TextField(
                        "Add 2 coffees and eggs",
                        text: $requestText,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .focused($isRequestTextFocused)
                    .padding(AppSpacing.medium)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                            .stroke(AppColors.panelBorder, lineWidth: 1)
                    }
                    .accessibilityLabel("Items to add")
                    .accessibilityHint("Type an item request, or use the Dictation microphone on the iOS keyboard.")

                    Text("For example: Add 2 coffees and eggs")
                        .font(.caption)
                        .foregroundStyle(AppColors.mutedText)
                }

                voiceInputControls

                if let errorMessage = viewModel.shoppingListReaddErrorMessage {
                    ErrorBannerView(message: errorMessage)
                }

                if viewModel.isShoppingListReaddUnavailable {
                    unavailableNotice
                } else if isFindingItems {
                    findingItemsNotice
                } else if let summary = viewModel.finalShoppingListReaddSummary {
                    ShoppingListReaddResultSummary(summary: summary)
                }

                actions
            }
            .padding(AppSpacing.screen)
        }
        .task {
            guard !viewModel.isShoppingListReaddActive,
                  !viewModel.isStartingShoppingListReadd else {
                return
            }

            isRequestTextFocused = true
        }
        .onChange(of: viewModel.isShoppingListReaddActive) { _, isActive in
            if !isActive {
                isRequestTextFocused = true
            }
        }
        .onChange(of: speechTranscription.transcript) { _, transcript in
            guard speechTranscription.isListening else {
                return
            }

            requestText = combinedRequestText(with: transcript)
        }
        .onChange(of: speechTranscription.state) { previousState, newState in
            if previousState.isListening && !newState.isListening {
                isRequestTextFocused = true
            }
        }
        .onDisappear {
            if speechTranscription.isCapturing {
                speechTranscription.cancelTranscribing()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 38, height: 38)
                .background(AppColors.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Add Items from Text")
                    .font(.title3.weight(.bold))

                Text("Use the keyboard’s Dictation microphone or type a quick request. AI only re-adds items already on this shared list.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var unavailableNotice: some View {
        Label("AI item matching is currently unavailable. You can still type or edit your request, but it cannot be submitted right now.", systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(BannerTone.warning.foregroundColor)
            .padding(AppSpacing.medium)
            .background(BannerTone.warning.backgroundColor, in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    private var voiceInputControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                Button {
                    if speechTranscription.isCapturing {
                        stopVoiceInput()
                    } else {
                        startVoiceInput()
                    }
                } label: {
                    Label(
                        speechTranscription.isCapturing ? "Stop Listening" : "Tap to Talk",
                        systemImage: speechTranscription.isCapturing ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(.white)
                    .background(speechTranscription.isCapturing ? AppColors.critical : AppColors.accent, in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    speechTranscription.isCapturing
                        ? "Stops voice input and leaves the recognized text ready to edit."
                        : "Requests access, then starts voice input. It never submits your request automatically."
                )

                if speechTranscription.isCapturing {
                    Button("Cancel Voice") {
                        cancelVoiceInput()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                    .buttonStyle(.plain)
                    .accessibilityHint("Discards only the current voice transcription and restores the text from before listening.")
                }
            }

            if let message = speechTranscription.state.message {
                Label(message, systemImage: speechStateSystemImage)
                    .font(.caption)
                    .foregroundStyle(speechStateTone.foregroundColor)
                    .padding(AppSpacing.small)
                    .background(speechStateTone.backgroundColor, in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                    .accessibilityElement(children: .combine)
            } else {
                Text(speechTranscription.usesOnDeviceRecognitionWhenAvailable
                    ? "Uses on-device speech recognition. You can edit before sending."
                    : "On-device speech recognition is unavailable. You can type your request instead.")
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
            }
        }
        .padding(AppSpacing.medium)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var findingItemsNotice: some View {
        Label("Finding items in your existing shopping list…", systemImage: "arrow.triangle.2.circlepath")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BannerTone.info.foregroundColor)
            .padding(AppSpacing.medium)
            .background(BannerTone.info.backgroundColor, in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: AppSpacing.small) {
            if let summary = viewModel.finalShoppingListReaddSummary,
               summary.undo.available {
                PrimaryActionButton(
                    title: viewModel.isUndoingShoppingListReadd ? "Undoing…" : "Undo Changes",
                    systemImage: "arrow.uturn.backward",
                    isLoading: viewModel.isUndoingShoppingListReadd
                ) {
                    Task { await viewModel.undoCurrentShoppingListReadd() }
                }
                .accessibilityHint("Safely reverts unchanged items from this AI request.")
            }

            PrimaryActionButton(
                title: submitButtonTitle,
                systemImage: "sparkles",
                isLoading: isFindingItems,
                isDisabled: isSubmitDisabled
            ) {
                Task { await viewModel.startShoppingListReadd(text: requestText) }
            }
            .accessibilityHint(submitAccessibilityHint)

            Button("Cancel") {
                dismiss()
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(AppColors.accent)
            .buttonStyle(.plain)
            .accessibilityHint("Closes Add Items from Text without changing the shopping list.")
        }
    }

    private var isFindingItems: Bool {
        viewModel.isStartingShoppingListReadd || viewModel.isShoppingListReaddActive
    }

    private var isSubmitDisabled: Bool {
        isFindingItems || viewModel.isShoppingListReaddUnavailable || requestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var submitButtonTitle: String {
        if isFindingItems {
            return "Finding Items…"
        }

        if viewModel.isShoppingListReaddUnavailable {
            return "AI Matching Unavailable"
        }

        return "Add to Shopping List"
    }

    private var submitAccessibilityHint: String {
        if viewModel.isShoppingListReaddUnavailable {
            return "AI item matching is unavailable, so this request cannot be submitted yet."
        }

        return "Finds the closest existing shopping-list items and adds them as needed."
    }

    private var speechStateSystemImage: String {
        switch speechTranscription.state {
        case .requestingPermission, .listening:
            return "mic.fill"
        case .denied, .unavailable, .interrupted, .failed:
            return "exclamationmark.triangle"
        case .idle:
            return "mic"
        }
    }

    private var speechStateTone: BannerTone {
        switch speechTranscription.state {
        case .requestingPermission, .listening:
            return .info
        case .denied, .unavailable, .interrupted, .failed:
            return .warning
        case .idle:
            return .info
        }
    }

    private func startVoiceInput() {
        textBeforeVoiceInput = requestText
        isRequestTextFocused = false
        Task { await speechTranscription.startTranscribing() }
    }

    private func stopVoiceInput() {
        speechTranscription.stopTranscribing()
        isRequestTextFocused = true
    }

    private func cancelVoiceInput() {
        speechTranscription.cancelTranscribing()
        requestText = textBeforeVoiceInput
        isRequestTextFocused = true
    }

    private func combinedRequestText(with transcript: String) -> String {
        ShoppingSpeechTranscriptComposer.combine(
            existingText: textBeforeVoiceInput,
            transcript: transcript
        )
    }
}

private struct ShoppingListReaddResultSummary: View {
    let summary: ShoppingListReaddSummary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: statusSystemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusTone.foregroundColor)
                    .frame(width: 34, height: 34)
                    .background(statusTone.backgroundColor, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !summary.operations.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    ForEach(summary.operations) { operation in
                        Label(operationDescription(operation), systemImage: operationSystemImage(operation))
                            .font(.subheadline)
                            .foregroundStyle(AppColors.text)
                            .accessibilityElement(children: .combine)
                    }
                }
            }

            if !summary.unmatched.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Not found in your existing list")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BannerTone.warning.foregroundColor)

                    ForEach(summary.unmatched) { phrase in
                        Text("• \(phrase.requestedText)")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.mutedText)
                    }
                }
                .padding(AppSpacing.medium)
                .background(BannerTone.warning.backgroundColor, in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
            }
        }
        .padding(AppSpacing.medium)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var appliedCount: Int {
        summary.operations.filter { operation in
            switch operation.outcome {
            case .reAdded, .quantityUpdated:
                return true
            case .alreadyNeeded, .unmatched, .staleSkipped, .invalidRequest, .unavailable, .undone, .unknown:
                return false
            }
        }.count
    }

    private var title: String {
        switch summary.status {
        case .undone:
            return "Changes Undone"
        case .failed:
            return "Couldn’t Update the List"
        case .completed, .completedWithIssues:
            return appliedCount == 1 ? "Added 1 Item" : "Added \(appliedCount) Items"
        case .queued, .matching, .applying, .unknown:
            return "Shopping List Update"
        }
    }

    private var subtitle: String {
        switch summary.status {
        case .undone:
            return "Eligible changes from this request were reverted."
        case .failed:
            return "Your shopping list was not changed by this request."
        case .completed, .completedWithIssues:
            if appliedCount == 0, !summary.unmatched.isEmpty {
                return "No matching existing items were found."
            }
            return "Only existing shopping-list items were considered."
        case .queued, .matching, .applying, .unknown:
            return "Your request is being checked against the existing shopping list."
        }
    }

    private var statusSystemImage: String {
        switch summary.status {
        case .undone:
            return "arrow.uturn.backward.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .completedWithIssues:
            return "exclamationmark.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .queued, .matching, .applying, .unknown:
            return "sparkles"
        }
    }

    private var statusTone: BannerTone {
        switch summary.status {
        case .failed:
            return .error
        case .completedWithIssues:
            return .warning
        case .queued, .matching, .applying, .unknown:
            return .info
        case .completed, .undone:
            return .success
        }
    }

    private func operationDescription(_ operation: ShoppingListReaddOperationSummary) -> String {
        let itemName = operation.itemName ?? operation.requestedText
        let quantityDescription = operation.quantity.map { " Quantity set to \($0)." } ?? ""

        switch operation.outcome {
        case .reAdded:
            return "\(itemName) added to needed items.\(quantityDescription)"
        case .quantityUpdated:
            return "\(itemName) quantity updated.\(quantityDescription)"
        case .alreadyNeeded:
            return "\(itemName) was already needed."
        case .unmatched:
            return "\(operation.requestedText) was not found in the existing list."
        case .staleSkipped:
            return "\(itemName) changed elsewhere and was not updated."
        case .invalidRequest, .unavailable:
            return "\(operation.requestedText) could not be updated."
        case .undone:
            return "\(itemName) was restored."
        case .unknown:
            return "\(itemName) needs review."
        }
    }

    private func operationSystemImage(_ operation: ShoppingListReaddOperationSummary) -> String {
        switch operation.outcome {
        case .reAdded:
            return "cart.badge.plus"
        case .quantityUpdated:
            return "number.circle"
        case .alreadyNeeded:
            return "checkmark.circle"
        case .unmatched, .staleSkipped, .invalidRequest, .unavailable:
            return "exclamationmark.triangle"
        case .undone:
            return "arrow.uturn.backward.circle"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

private struct ShoppingAIFloatingEntry: View {
    let status: ShoppingAIStatus?
    let isUnavailable: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.small) {
            if let status {
                Label {
                    Text(status.message)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: status.systemImage)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.tone.foregroundColor)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .background(status.tone.backgroundColor, in: Capsule(style: .continuous))
                .accessibilityElement(children: .combine)
            }

            Button(action: action) {
                ZStack {
                    VStack(spacing: 1) {
                        Image(systemName: "sparkles")
                            .font(.headline.weight(.bold))

                        Text("AI")
                            .font(.caption2.weight(.bold))
                    }

                    if isUnavailable {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 49, height: 3)
                            .rotationEffect(.degrees(-45))
                            .shadow(color: AppColors.accent.opacity(0.35), radius: 1)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 58, height: 58)
                .foregroundStyle(Color.white.opacity(isUnavailable ? 0.72 : 1))
                .background(AppColors.accent.opacity(isUnavailable ? 0.45 : 1), in: Circle())
                .overlay {
                    Circle()
                        .stroke(
                            isUnavailable ? AppColors.mutedText.opacity(0.7) : AppColors.panelBackground.opacity(0.8),
                            lineWidth: 1
                        )
                }
                .shadow(color: AppColors.surfaceShadow.opacity(isUnavailable ? 0.35 : 0.7), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(isUnavailable)
            .accessibilityLabel(isUnavailable ? "Shopping AI unavailable" : "Shopping AI")
            .accessibilityValue(isUnavailable ? "Unavailable" : (status?.message ?? "Ready"))
            .accessibilityHint(
                isUnavailable
                    ? "Stock and price checking is not available yet."
                    : "Opens Shopping AI actions"
            )
        }
        .frame(maxWidth: 300, alignment: .trailing)
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

private struct ShoppingListFilterSheet: View {
    @Binding var filters: ShoppingListFilters
    let onClear: () -> Void
    let onApply: () -> Void

    @State private var isStatusExpanded = true
    @State private var isStoreExpanded = true
    @State private var isViewExpanded = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.medium) {
                        ShoppingFilterAccordionSection(
                            title: "View",
                            systemImage: "rectangle.3.group",
                            isExpanded: $isViewExpanded
                        ) {
                            VStack(spacing: AppSpacing.small) {
                                ForEach(ShoppingListViewMode.allCases) { viewMode in
                                    ShoppingFilterOptionRow(
                                        title: viewMode.title,
                                        systemImage: viewMode.systemImage,
                                        isSelected: filters.viewMode == viewMode
                                    ) {
                                        filters.viewMode = viewMode
                                    }
                                }
                            }
                        }

                        ShoppingFilterAccordionSection(
                            title: "Status",
                            systemImage: "checkmark.circle",
                            isExpanded: $isStatusExpanded
                        ) {
                            ShoppingFilterOptionRow(
                                title: "Needed",
                                systemImage: "cart.badge.plus",
                                isSelected: filters.neededOnly
                            ) {
                                filters.neededOnly.toggle()
                            }
                        }

                        ShoppingFilterAccordionSection(
                            title: "Store",
                            systemImage: "storefront",
                            isExpanded: $isStoreExpanded
                        ) {
                            VStack(spacing: AppSpacing.small) {
                                ForEach(ShoppingStoreFilterOption.allCases) { store in
                                    ShoppingFilterOptionRow(
                                        title: store.title,
                                        systemImage: store.systemImage,
                                        isSelected: filters.selectedStores.contains(store)
                                    ) {
                                        filters.toggleStore(store)
                                    }
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.screen)
                }

                Divider()

                HStack(spacing: AppSpacing.medium) {
                    Button(action: onClear) {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(AppColors.accent)
                            .background(AppColors.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: onApply) {
                        Label("Apply", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(Color.white)
                            .background(AppColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.screen)
                .padding(.vertical, AppSpacing.medium)
                .background(AppColors.pageBackground)
            }
            .background(AppColors.pageBackground)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ShoppingFilterAccordionSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    private let content: () -> Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        _isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                content()
            }
            .padding(.top, AppSpacing.medium)
        } label: {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 24)

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .tint(AppColors.accent)
        .padding(AppSpacing.medium)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ShoppingFilterOptionRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.mutedText)
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: AppSpacing.small)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 48)
            .background(isSelected ? AppColors.accentSoft : AppColors.insetPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

fileprivate struct ShoppingListFilters: Equatable {
    var viewMode: ShoppingListViewMode = .detailed
    var neededOnly = false
    var selectedStores: Set<ShoppingStoreFilterOption> = []

    var isActive: Bool {
        viewMode != .detailed || neededOnly || !selectedStores.isEmpty
    }

    mutating func toggleStore(_ store: ShoppingStoreFilterOption) {
        if selectedStores.contains(store) {
            selectedStores.remove(store)
        } else {
            selectedStores.insert(store)
        }
    }

    func matches(
        _ displayItem: ShoppingListDisplayItem,
        storesById: [Int: ShoppingStore]
    ) -> Bool {
        if neededOnly && displayItem.item.purchased {
            return false
        }

        return selectedStores.allSatisfy { store in
            displayItem.matches(storeFilter: store, storesById: storesById)
        }
    }
}

fileprivate enum ShoppingListViewMode: String, CaseIterable, Identifiable {
    case detailed
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .detailed:
            return "Detailed"
        case .compact:
            return "Compact"
        }
    }

    var systemImage: String {
        switch self {
        case .detailed:
            return "rectangle.3.group"
        case .compact:
            return "list.bullet"
        }
    }
}

fileprivate enum ShoppingStoreFilterOption: String, CaseIterable, Identifiable {
    case kingSoopers
    case target

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kingSoopers:
            return "King Soopers"
        case .target:
            return "Target"
        }
    }

    var systemImage: String {
        switch self {
        case .kingSoopers:
            return "basket.fill"
        case .target:
            return "cart.fill"
        }
    }

    func matches(
        listing: ShoppingItemStoreListing,
        fallbackStore: ShoppingStore?
    ) -> Bool {
        let searchableValues = [
            listing.storeName,
            fallbackStore?.name,
            listing.source,
            listing.krogerLocationId,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        if searchableValues.contains(where: matchesStoreName) {
            return true
        }

        switch self {
        case .kingSoopers:
            return listing.storeId == 2
        case .target:
            return listing.storeId == 1
        }
    }

    private func matchesStoreName(_ value: String) -> Bool {
        switch self {
        case .kingSoopers:
            return value.contains("king soopers")
                || value.contains("kingsoopers")
                || value.contains("kroger")
        case .target:
            return value.contains("target")
        }
    }
}

private struct ShoppingListSummaryCard: View {
    let residentAvatars: [ResidentAvatarState]
    let activeTrip: ShoppingTrip?
    let remainingText: String
    let estimatedTotalText: String
    let isFilterActive: Bool
    let isTripActionInFlight: Bool
    let onStartShop: () -> Void
    let onEndShop: () -> Void
    let onFilter: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            ResidentAvatarStack(avatars: residentAvatars)
                .frame(minWidth: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(remainingText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Text(estimatedTotalText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .layoutPriority(1)

            Spacer(minLength: AppSpacing.small)

            Button(action: activeTrip == nil ? onStartShop : onEndShop) {
                Label(activeTrip == nil ? "New" : "End Shop", systemImage: activeTrip == nil ? "cart.fill" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, AppSpacing.medium)
                    .frame(height: 34)
                    .foregroundStyle(Color.white)
                    .background(AppColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isTripActionInFlight)
            .opacity(isTripActionInFlight ? 0.65 : 1)
            .accessibilityLabel(activeTrip == nil ? "Start new shopping run" : "End shopping run")

            Button(action: onFilter) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(isFilterActive ? Color.white : AppColors.accent)
                    .background(isFilterActive ? AppColors.accent : AppColors.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter shopping list")
            .accessibilityValue(isFilterActive ? "Active" : "Inactive")
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
    @State private var isProductSearchPresented = false
    @State private var manualStorePriceText: [Int: String]
    @State private var expandedManualStoreDetailIDs: Set<Int>

    init(mode: ShoppingItemEditorMode, viewModel: ShoppingListViewModel) {
        self.mode = mode
        self.viewModel = viewModel
        let initialDraft = mode.editingItem.map {
            ShoppingItemDraft(item: $0, defaultCategoryId: viewModel.defaultShoppingCategoryId)
        } ?? ShoppingItemDraft(selectedCategoryId: viewModel.defaultShoppingCategoryId)
        let initialExpandedManualStoreIDs = Set(
            viewModel.stores
                .filter { initialDraft.selectedStoreIds.contains($0.id) && !$0.isKrogerBacked }
                .map(\.id)
        )
        _draft = State(initialValue: initialDraft)
        _manualStorePriceText = State(initialValue: initialDraft.manualPriceTextByStoreId)
        _expandedManualStoreDetailIDs = State(initialValue: initialExpandedManualStoreIDs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    storePicker

                    nameField

                    productLookupSection

                    manualStoreDetailsSection

                    duplicateStatusView

                    quantityControl

                    categoryPicker

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
            .sheet(isPresented: $isProductSearchPresented) {
                ShoppingProductSearchSheet(
                    initialSearchTerm: draft.trimmedName,
                    viewModel: viewModel
                ) { product in
                    draft.apply(product: product, kingSoopersStore: kingSoopersStore)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        } else if didFailDuplicateLookup {
            ErrorBannerView(
                message: "Could not verify duplicates. The final save will still use the server check.",
                tone: .warning
            )
        } else {
            Label("Checking duplicates", systemImage: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(AppColors.mutedText)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .opacity(isCheckingDuplicate ? 1 : 0)
                .accessibilityHidden(!isCheckingDuplicate)
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
            if viewModel.categories.isEmpty {
                Text("No categories available")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.mutedText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.small) {
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
                .onAppear {
                    if draft.selectedCategoryId == nil {
                        draft.selectedCategoryId = viewModel.defaultShoppingCategoryId
                    }
                }
                .onChange(of: viewModel.defaultShoppingCategoryId) { defaultCategoryId in
                    if draft.selectedCategoryId == nil {
                        draft.selectedCategoryId = defaultCategoryId
                    }
                }
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
                                let wasSelected = draft.selectedStoreIds.contains(store.id)
                                draft.toggleStore(store)

                                if wasSelected {
                                    manualStorePriceText[store.id] = nil
                                    expandedManualStoreDetailIDs.remove(store.id)
                                } else {
                                    if manualStorePriceText[store.id] == nil {
                                        manualStorePriceText[store.id] = draft.manualPriceText(for: store)
                                    }

                                    if !store.isKrogerBacked {
                                        expandedManualStoreDetailIDs.insert(store.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    @ViewBuilder
    private var manualStoreDetailsSection: some View {
        let stores = manualStoreDetailCandidates

        if !stores.isEmpty {
            ShoppingFormSection(title: manualStoreDetailsTitle(for: stores)) {
                VStack(spacing: AppSpacing.small) {
                    ForEach(stores) { store in
                        ShoppingManualStoreDetailsDisclosure(
                            storeName: store.name,
                            isSelected: draft.selectedStoreIds.contains(store.id),
                            isExpanded: expandedManualStoreDetailIDs.contains(store.id),
                            onToggle: {
                                toggleManualStoreDetails(for: store)
                            }
                        ) {
                            ShoppingManualStoreDetailsEditor(
                                aisleNumber: Binding(
                                    get: { draft.manualAisleNumber(for: store) },
                                    set: { draft.updateManualAisleNumber($0, for: store) }
                                ),
                                shelfNumber: Binding(
                                    get: { draft.manualShelfNumber(for: store) },
                                    set: { draft.updateManualShelfNumber($0, for: store) }
                                ),
                                priceText: Binding(
                                    get: { manualStorePriceText[store.id] ?? draft.manualPriceText(for: store) },
                                    set: { value in
                                        manualStorePriceText[store.id] = value
                                        draft.updateManualPriceText(value, for: store)
                                    }
                                )
                            )
                            .padding(.top, AppSpacing.xSmall)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: expandedManualStoreDetailIDs)
            }
        }
    }

    private func manualStoreDetailsTitle(for stores: [ShoppingStore]) -> String {
        guard stores.count == 1, let store = stores.first else {
            return "Other Store Details"
        }

        return "\(store.name) Details"
    }

    private var kingSoopersStore: ShoppingStore? {
        viewModel.stores.first(where: \.isKrogerBacked)
    }

    private var manualStoreDetailCandidates: [ShoppingStore] {
        viewModel.stores.filter { !$0.isKrogerBacked }
    }

    private var productLookupSection: some View {
        ShoppingFormSection(title: "Product") {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                if let selectedKrogerProductName = draft.selectedKrogerProductName {
                    Label(selectedKrogerProductName, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.success)
                        .lineLimit(2)
                } else {
                    Text("Optional")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                }

                Button {
                    isProductSearchPresented = true
                } label: {
                    Label("Find at King Soopers", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmedName.isEmpty && draft.selectedKrogerProductName == nil)
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

    private func toggleManualStoreDetails(for store: ShoppingStore) {
        if !draft.selectedStoreIds.contains(store.id) {
            draft.toggleStore(store)
            manualStorePriceText[store.id] = draft.manualPriceText(for: store)
            expandedManualStoreDetailIDs.insert(store.id)
            return
        }

        if expandedManualStoreDetailIDs.contains(store.id) {
            expandedManualStoreDetailIDs.remove(store.id)
        } else {
            expandedManualStoreDetailIDs.insert(store.id)
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
                try await viewModel.updateItem(item, with: draft)
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

private struct ShoppingManualStoreDetailsDisclosure<Content: View>: View {
    let storeName: String
    let isSelected: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    init(
        storeName: String,
        isSelected: Bool,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.storeName = storeName
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Button(action: onToggle) {
                HStack(spacing: AppSpacing.medium) {
                    StatusBadgeView(label: storeName, systemImage: "mappin.circle", tone: .neutral)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSelected ? "\(storeName) details" : "Add \(storeName) details")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Price, aisle, and shelf")
                            .font(.caption)
                            .foregroundStyle(AppColors.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.mutedText)
                }
                .padding(AppSpacing.medium)
                .background(AppColors.insetPanelBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                        .stroke(AppColors.panelBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if isSelected && isExpanded {
                content
            }
        }
    }
}

private struct ShoppingManualStoreDetailsEditor: View {
    @Binding var aisleNumber: String
    @Binding var shelfNumber: String
    @Binding var priceText: String

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            manualField(
                title: "Price",
                placeholder: "7.49",
                text: $priceText,
                keyboardType: .decimalPad
            )

            manualField(
                title: "Aisle",
                placeholder: "G23",
                text: $aisleNumber,
                keyboardType: .default
            )

            manualField(
                title: "Shelf",
                placeholder: "2",
                text: $shelfNumber,
                keyboardType: .numbersAndPunctuation
            )
        }
        .padding(AppSpacing.medium)
        .background(AppColors.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }

    private func manualField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.mutedText)

            TextField(placeholder, text: text)
                .font(.subheadline.weight(.semibold))
                .textInputAutocapitalization(.characters)
                .keyboardType(keyboardType)
                .padding(.horizontal, AppSpacing.small)
                .frame(height: 36)
                .background(AppColors.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous)
                        .stroke(AppColors.panelBorder, lineWidth: 1)
                }
        }
    }
}

private struct ShoppingProductSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialSearchTerm: String
    @ObservedObject var viewModel: ShoppingListViewModel
    let onSelect: (KrogerProduct) -> Void

    @State private var searchTerm: String
    @State private var products: [KrogerProduct] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var productForDetails: KrogerProduct?

    init(
        initialSearchTerm: String,
        viewModel: ShoppingListViewModel,
        onSelect: @escaping (KrogerProduct) -> Void
    ) {
        self.initialSearchTerm = initialSearchTerm
        self.viewModel = viewModel
        self.onSelect = onSelect
        _searchTerm = State(initialValue: initialSearchTerm)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    searchField

                    if let errorMessage {
                        ErrorBannerView(message: errorMessage, tone: .warning)
                    }

                    if isSearching {
                        HStack(spacing: AppSpacing.medium) {
                            ProgressView()

                            Text("Searching King Soopers...")
                                .font(.body)
                                .foregroundStyle(AppColors.mutedText)
                        }
                        .padding(AppSpacing.medium)
                    } else if products.isEmpty && hasSearched {
                        InfoPanel(
                            title: "No Products Found",
                            subtitle: "Try a shorter product name or brand.",
                            systemImage: "magnifyingglass"
                        ) {
                            EmptyView()
                        }
                    } else {
                        LazyVStack(spacing: AppSpacing.small) {
                            ForEach(products, id: \.stableSearchId) { product in
                                ShoppingProductResultRow(
                                    product: product,
                                    onShowDetails: {
                                        productForDetails = product
                                    },
                                    onSelect: {
                                        onSelect(product)
                                        dismiss()
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(AppSpacing.screen)
            }
            .background(AppColors.pageBackground)
            .navigationTitle("Find Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await searchIfReady()
            }
            .sheet(
                isPresented: Binding(
                    get: { productForDetails != nil },
                    set: { isPresented in
                        if !isPresented {
                            productForDetails = nil
                        }
                    }
                )
            ) {
                if let productForDetails {
                    ShoppingProductDetailSheet(product: productForDetails)
                }
            }
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(AppColors.mutedText)
                    .frame(width: 24)

                TextField("Search Kroger products", text: $searchTerm)
                    .font(.body)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            await search()
                        }
                    }

                if !searchTerm.isEmpty {
                    Button {
                        searchTerm = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.mutedText)
                    }
                    .accessibilityLabel("Clear product search")
                }
            }
            .padding(AppSpacing.medium)
            .background(AppColors.insetPanelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                    .stroke(AppColors.panelBorder, lineWidth: 1)
            }

            PrimaryActionButton(
                title: "Search",
                systemImage: "magnifyingglass",
                isLoading: isSearching,
                isDisabled: trimmedSearchTerm.isEmpty || isSearching
            ) {
                Task {
                    await search()
                }
            }
        }
    }

    private var trimmedSearchTerm: String {
        searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchIfReady() async {
        guard !trimmedSearchTerm.isEmpty else {
            return
        }

        await search()
    }

    private func search() async {
        let term = trimmedSearchTerm

        guard !term.isEmpty, !isSearching else {
            return
        }

        isSearching = true
        errorMessage = nil

        defer {
            isSearching = false
            hasSearched = true
        }

        do {
            products = try await viewModel.searchProducts(named: term)
        } catch {
            products = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShoppingProductResultRow: View {
    let product: KrogerProduct
    let onShowDetails: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Button(action: onShowDetails) {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    KrogerProductImage(imageURL: product.image, size: 56)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text(product.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let brand = product.trimmedBrand {
                            Text(brand)
                                .font(.caption)
                                .foregroundStyle(AppColors.mutedText)
                                .lineLimit(1)
                        }

                        HStack(spacing: AppSpacing.xSmall) {
                            if let aisleDisplay = product.primaryListing?.aisle?.display {
                                StatusBadgeView(label: aisleDisplay, systemImage: "mappin.circle", tone: .accent)
                            }

                            if let priceText = product.primaryListing?.price?.displayText {
                                StatusBadgeView(label: priceText, systemImage: "tag", tone: .success)
                            }
                        }
                    }

                    Spacer(minLength: AppSpacing.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View details for \(product.displayName)")

            Button(action: onSelect) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(product.displayName)")
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

private struct ShoppingProductDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let product: KrogerProduct

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    KrogerProductImage(imageURL: product.image, size: 220)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text(product.displayName)
                            .font(.title2.weight(.bold))

                        if let brand = product.trimmedBrand {
                            Text(brand)
                                .font(.body)
                                .foregroundStyle(AppColors.mutedText)
                        }
                    }

                    if let description = product.detailDescription {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(AppColors.mutedText)
                    }

                    if !productDetails.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(productDetails.enumerated()), id: \.offset) { index, detail in
                                ShoppingProductDetailRow(
                                    title: detail.title,
                                    value: detail.value,
                                    systemImage: detail.systemImage
                                )

                                if index < productDetails.count - 1 {
                                    Divider()
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
                .padding(AppSpacing.screen)
            }
            .background(AppColors.pageBackground)
            .navigationTitle("Product Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var productDetails: [(title: String, value: String, systemImage: String)] {
        var details: [(title: String, value: String, systemImage: String)] = []

        if let price = product.primaryListing?.price?.displayText {
            details.append(("Price", price, "tag"))
        }

        if let store = product.primaryListing?.storeName {
            details.append(("Store", store, "building.2"))
        }

        if let aisle = product.primaryListing?.aisle?.display {
            details.append(("Aisle", aisle, "mappin.circle"))
        }

        if let availability = product.primaryListing?.availability?.status?.productDetailDisplayValue {
            details.append(("Availability", availability, "checkmark.circle"))
        }

        if let upc = product.upc?.trimmingCharacters(in: .whitespacesAndNewlines), !upc.isEmpty {
            details.append(("UPC", upc, "barcode"))
        }

        return details
    }
}

private struct ShoppingProductDetailRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColors.accent)
                .frame(width: 20)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppColors.mutedText)
                .multilineTextAlignment(.trailing)
        }
        .padding(AppSpacing.medium)
    }
}

private struct KrogerProductImage: View {
    let imageURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(AppColors.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "shippingbox")
            .font(.title)
            .foregroundStyle(AppColors.mutedText)
    }
}

private struct ShoppingCategorySection: View {
    let group: ShoppingCategoryGroup
    let mutatingItemIDs: Set<Int>
    let onTogglePurchased: (ShoppingListItem) -> Void
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

private struct ShoppingCompactSection: View {
    let title: String
    let systemImage: String
    let items: [ShoppingListDisplayItem]
    let mutatingItemIDs: Set<Int>
    let onTogglePurchased: (ShoppingListItem) -> Void
    let onEdit: (ShoppingListItem) -> Void
    let onDelete: (ShoppingListItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.accent)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)

            Divider()
                .padding(.leading, AppSpacing.large)

            ForEach(items) { item in
                ShoppingCompactItemRow(
                    displayItem: item,
                    isMutating: mutatingItemIDs.contains(item.item.id),
                    onTogglePurchased: {
                        onTogglePurchased(item.item)
                    },
                    onEdit: {
                        onEdit(item.item)
                    },
                    onDelete: {
                        onDelete(item.item)
                    }
                )

                if item.id != items.last?.id {
                    Divider()
                        .padding(.leading, 54)
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

            ShoppingItemThumbnail(imageURL: displayItem.item.image, size: 42)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(displayItem.item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(displayItem.item.purchased ? AppColors.mutedText : .primary)
                    .strikethrough(displayItem.item.purchased, color: AppColors.mutedText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)

                if let detailText = displayItem.detailText {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !displayItem.storeListings.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        ForEach(displayItem.storeListings) { listing in
                            ShoppingStoreListingSummaryRow(listing: listing)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: AppSpacing.medium) {
                if isMutating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    RowQuantityBadge(quantity: displayItem.item.quantity)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.mutedText)
                }
            }
            .frame(minWidth: 54, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
        .padding(AppSpacing.medium)
        .background(AppColors.panelBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayItem.accessibilityLabel)
        .accessibilityAction(named: Text("Delete"), onDelete)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
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

private struct ShoppingCompactItemRow: View {
    let displayItem: ShoppingListDisplayItem
    let isMutating: Bool
    let onTogglePurchased: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Button(action: onTogglePurchased) {
                Image(systemName: displayItem.item.purchased ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(displayItem.item.purchased ? AppColors.success : AppColors.accent)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(isMutating)
            .accessibilityLabel(displayItem.item.purchased ? "Mark needed" : "Mark picked up")

            ShoppingItemThumbnail(imageURL: displayItem.item.image, size: 34)

            Text(displayItem.item.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(displayItem.item.purchased ? AppColors.mutedText : .primary)
                .strikethrough(displayItem.item.purchased, color: AppColors.mutedText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isMutating {
                ProgressView()
                    .controlSize(.small)
            } else {
                RowQuantityBadge(quantity: displayItem.item.quantity)
            }
        }
        .padding(AppSpacing.medium)
        .background(AppColors.panelBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayItem.compactAccessibilityLabel)
        .accessibilityAction(named: Text("Delete"), onDelete)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
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

private struct ShoppingItemThumbnail: View {
    let imageURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(AppColors.insetPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "shippingbox")
            .font(.headline)
            .foregroundStyle(AppColors.mutedText)
    }
}

private struct ShoppingStoreListingSummaryRow: View {
    let listing: ShoppingItemStoreListing

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.xSmall) {
                    storePill
                    aislePill
                    pricePill
                }

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    HStack(spacing: AppSpacing.xSmall) {
                        storePill
                        aislePill
                    }
                    pricePill
                }
            }

            if let freshnessText = ShoppingStoreListingPresentation.freshnessText(for: listing) {
                Text(freshnessText)
                    .font(.caption)
                    .foregroundStyle(AppColors.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShoppingStoreListingPresentation.accessibilityLabel(for: listing))
    }

    private var storePill: some View {
        let tone = ShoppingStoreListingPresentation.availabilityTone(for: listing)

        return Text(ShoppingStoreListingPresentation.storeName(for: listing))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, AppSpacing.small)
            .frame(height: 24)
            .foregroundStyle(tone.foregroundColor)
            .background(tone.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
    }

    @ViewBuilder
    private var aislePill: some View {
        if let aisleText = ShoppingStoreListingPresentation.locationText(for: listing) {
            Label(aisleText, systemImage: "mappin.circle")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, AppSpacing.small)
                .frame(height: 24)
                .foregroundStyle(AppColors.mutedText)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
        }
    }

    @ViewBuilder
    private var pricePill: some View {
        if let priceText = ShoppingStoreListingPresentation.priceText(for: listing) {
            Text(priceText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()
                .padding(.horizontal, AppSpacing.small)
                .frame(height: 24)
                .foregroundStyle(AppColors.mutedText)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
        }
    }
}

private struct ShoppingStockPriceCheckSummarySheet: View {
    let summary: ShoppingStockPriceCheckSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: statusSystemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(statusTone.foregroundColor)
                    .frame(width: 38, height: 38)
                    .background(statusTone.backgroundColor, in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(title)
                        .font(.title3.weight(.bold))

                    Text("Review the availability, location, and price details on the affected shopping-list entries before you shop.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: AppSpacing.small) {
                ShoppingStockPriceCheckCount(label: "Updated", count: summary.updatedItemCount, tone: .success)
                ShoppingStockPriceCheckCount(label: "Needs review", count: summary.unmatchedItemCount, tone: .warning)
                ShoppingStockPriceCheckCount(label: "Failed", count: summary.failedItemCount, tone: .critical)
            }

            if summary.skippedStaleItemCount > 0 {
                ShoppingStockPriceCheckCount(
                    label: "Skipped stale",
                    count: summary.skippedStaleItemCount,
                    tone: .neutral
                )
            }

            PrimaryActionButton(title: "Done", systemImage: "checkmark", action: onDismiss)
        }
        .padding(AppSpacing.screen)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch summary.status {
        case .completed:
            return "Stock & Price Check Complete"
        case .completedWithIssues:
            return "Stock & Price Check Needs Review"
        case .failed:
            return "Stock & Price Check Did Not Finish"
        case .queued, .running, .unknown:
            return "Stock & Price Check Update"
        }
    }

    private var statusSystemImage: String {
        switch summary.status {
        case .completed:
            return "checkmark.circle"
        case .completedWithIssues:
            return "exclamationmark.circle"
        case .failed:
            return "xmark.octagon"
        case .queued, .running, .unknown:
            return "info.circle"
        }
    }

    private var statusTone: StatusBadgeTone {
        switch summary.status {
        case .completed:
            return .success
        case .completedWithIssues:
            return .warning
        case .failed:
            return .critical
        case .queued, .running, .unknown:
            return .neutral
        }
    }
}

private struct ShoppingStockPriceCheckCount: View {
    let label: String
    let count: Int
    let tone: StatusBadgeTone

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(tone.foregroundColor)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(AppSpacing.small)
        .background(tone.backgroundColor, in: RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(count)")
    }
}

private struct RowQuantityBadge: View {
    let quantity: Int

    var body: some View {
        Text("Qty \(quantity)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, AppSpacing.small)
            .frame(height: 28)
            .background(AppColors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous)
                    .stroke(AppColors.panelBorder, lineWidth: 1)
            }
    }
}

private struct ShoppingCategoryGroup: Identifiable {
    let category: ShoppingCategory
    let items: [ShoppingListDisplayItem]

    var id: ShoppingCategory { category }
}

struct ShoppingListDisplayItem: Identifiable, Comparable {
    let item: ShoppingListItem
    let category: ShoppingCategory

    var id: Int { item.id }

    var storeListings: [ShoppingItemStoreListing] {
        ShoppingStoreListingPresentation.coalescedListings(from: item.storeListings)
    }

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
        let storeDetails = storeListings
            .map { ShoppingStoreListingPresentation.accessibilityLabel(for: $0) }
            .joined(separator: "; ")
        let storesText = storeDetails.isEmpty ? "" : ", \(storeDetails)"

        return "\(item.name), quantity \(item.quantity), \(category.name), \(state)\(storesText)"
    }

    var compactAccessibilityLabel: String {
        let state = item.purchased ? "picked up" : "needed"
        let storeDetails = storeListings
            .map { ShoppingStoreListingPresentation.accessibilityLabel(for: $0) }
            .joined(separator: "; ")
        let storesText = storeDetails.isEmpty ? "" : ", \(storeDetails)"
        return "\(item.name), quantity \(item.quantity), \(state)\(storesText)"
    }

    func matches(_ searchText: String) -> Bool {
        let searchableValues = [
            item.name,
            item.brand,
            item.notes,
            category.name,
            item.image,
        ] + storeListings.flatMap(\.searchableValues)

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

    static func isMoreRecentlyActive(_ lhs: ShoppingListDisplayItem, _ rhs: ShoppingListDisplayItem) -> Bool {
        let lhsTimestamp = lhs.item.updated ?? lhs.item.created ?? ""
        let rhsTimestamp = rhs.item.updated ?? rhs.item.created ?? ""

        if lhsTimestamp != rhsTimestamp {
            return lhsTimestamp > rhsTimestamp
        }

        let lhsVersion = lhs.item.version ?? 0
        let rhsVersion = rhs.item.version ?? 0

        if lhsVersion != rhsVersion {
            return lhsVersion > rhsVersion
        }

        return lhs.item.id > rhs.item.id
    }
}

private extension ShoppingListDisplayItem {
    func matches(
        storeFilter: ShoppingStoreFilterOption,
        storesById: [Int: ShoppingStore]
    ) -> Bool {
        storeListings.contains { listing in
            let fallbackStore = listing.storeId.flatMap { storesById[$0] }

            return storeFilter.matches(listing: listing, fallbackStore: fallbackStore)
        }
    }
}

private extension KrogerProduct {
    var displayName: String {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)

        return name?.nilIfEmpty ?? description?.nilIfEmpty ?? "Kroger product"
    }

    var trimmedBrand: String? {
        brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var detailDescription: String? {
        guard let description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              description.localizedCaseInsensitiveCompare(displayName) != .orderedSame else {
            return nil
        }

        return description
    }

    var stableSearchId: String {
        productId ?? upc ?? productPageURI ?? name ?? description ?? "unknown-product"
    }

    var primaryListing: ShoppingItemStoreListing? {
        storeListings.first
    }
}

struct ShoppingStoreListingPresentation {
    private enum CanonicalStore: Hashable {
        case target
        case kingSoopers
        case other(String)
    }

    private static let targetAddressFragment = "1365 sgt jon stiles dr"
    private static let kingSoopersAddressFragment = "2205 w wildcat reserve pkwy"

    static func coalescedListings(from listings: [ShoppingItemStoreListing]) -> [ShoppingItemStoreListing] {
        let indexed = Array(listings.enumerated())
        let grouped = Dictionary(grouping: indexed) { canonicalStore(for: $0.element) }

        return grouped
            .sorted { first, second in
                first.value.map(\.offset).min() ?? 0 < second.value.map(\.offset).min() ?? 0
            }
            .compactMap { _, candidates in
                preferredListing(from: candidates.map(\.element))
            }
    }

    static func storeName(for listing: ShoppingItemStoreListing) -> String {
        switch canonicalStore(for: listing) {
        case .target:
            return "Target"
        case .kingSoopers:
            return "King Soopers"
        case .other:
            return trimmedNonEmpty(listing.storeName) ?? "Store"
        }
    }

    static func availabilityLabel(for listing: ShoppingItemStoreListing) -> String {
        switch listing.availability?.normalizedStatus ?? .unknown("unknown") {
        case .inStock:
            return "In stock"
        case .lowStock:
            return "Low stock"
        case .outOfStock:
            return "Out of stock"
        case .unknown:
            return "Availability unknown"
        }
    }

    static func availabilityTone(for listing: ShoppingItemStoreListing) -> StatusBadgeTone {
        switch listing.availability?.normalizedStatus ?? .unknown("unknown") {
        case .inStock:
            return .success
        case .lowStock:
            return .warning
        case .outOfStock:
            return .critical
        case .unknown:
            return .neutral
        }
    }

    static func priceText(for listing: ShoppingItemStoreListing) -> String? {
        estimatedUnitPrice(for: listing)?.formatted(.currency(code: "USD"))
    }

    static func locationText(for listing: ShoppingItemStoreListing) -> String? {
        trimmedNonEmpty(listing.aisle?.display) ?? trimmedNonEmpty(listing.aisle?.description)
    }

    static func freshnessText(for listing: ShoppingItemStoreListing, now: Date = .now) -> String? {
        guard let checkedAt = checkedAtDate(for: listing) else {
            return nil
        }

        let seconds = now.timeIntervalSince(checkedAt)

        guard seconds >= 0 else {
            return "Checked just now"
        }

        if seconds < 60 {
            return "Checked just now"
        }

        if seconds < 3_600 {
            return "Checked \(Int(seconds / 60))m ago"
        }

        if seconds < 86_400 {
            return "Checked \(Int(seconds / 3_600))h ago"
        }

        return "Last checked \(Int(seconds / 86_400))d ago"
    }

    static func contextText(for listing: ShoppingItemStoreListing, now: Date = .now) -> String? {
        [
            locationText(for: listing).map { "Location: \($0)" },
            freshnessText(for: listing, now: now),
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
        .nilIfEmpty
    }

    static func accessibilityLabel(for listing: ShoppingItemStoreListing, now: Date = .now) -> String {
        var details = [storeName(for: listing), availabilityLabel(for: listing)]

        if let location = locationText(for: listing) {
            details.append("location \(location)")
        }

        if let price = priceText(for: listing) {
            details.append("price \(price)")
        }

        if let freshness = freshnessText(for: listing, now: now) {
            details.append(freshness)
        } else {
            details.append("freshness unavailable")
        }

        return details.joined(separator: ", ")
    }

    static func estimatedUnitPrice(for listing: ShoppingItemStoreListing) -> Double? {
        validPrice(listing.price?.promo) ?? validPrice(listing.price?.regular)
    }

    private static func preferredListing(from candidates: [ShoppingItemStoreListing]) -> ShoppingItemStoreListing? {
        let verifiedListings = candidates.filter(isVerifiedFixedStoreListing)

        if let verifiedListing = verifiedListings.max(by: { checkedAtDate(for: $0) ?? .distantPast < checkedAtDate(for: $1) ?? .distantPast }) {
            return verifiedListing
        }

        if let manualListing = candidates.first(where: isManualListing) {
            return manualListing
        }

        return candidates.max(by: { checkedAtDate(for: $0) ?? .distantPast < checkedAtDate(for: $1) ?? .distantPast })
    }

    private static func canonicalStore(for listing: ShoppingItemStoreListing) -> CanonicalStore {
        let values = [listing.storeName, listing.source, listing.krogerLocationId]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        if listing.storeId == 1 || values.contains(where: { $0.contains("target") }) {
            return .target
        }

        if listing.storeId == 2 || values.contains(where: {
            $0.contains("king soopers") || $0.contains("kingsoopers") || $0.contains("kroger")
        }) {
            return .kingSoopers
        }

        return .other("\(listing.storeId.map(String.init) ?? "")\u{0}\(listing.storeName?.lowercased() ?? "")\u{0}\(listing.source?.lowercased() ?? "")")
    }

    private static func isVerifiedFixedStoreListing(_ listing: ShoppingItemStoreListing) -> Bool {
        let source = listing.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let address = listing.selectedStoreAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        switch canonicalStore(for: listing) {
        case .target:
            return source == "target.com" && address.contains(targetAddressFragment)
        case .kingSoopers:
            return source == "kingsoopers.com" && address.contains(kingSoopersAddressFragment)
        case .other:
            return false
        }
    }

    private static func isManualListing(_ listing: ShoppingItemStoreListing) -> Bool {
        listing.source?.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("manual") == .orderedSame
    }

    private static func checkedAtDate(for listing: ShoppingItemStoreListing) -> Date? {
        let value = listing.availability?.checkedAt ?? listing.checkedAt
        guard let value = trimmedNonEmpty(value) else {
            return nil
        }

        return ISO8601DateFormatter().date(from: value)
    }

    private static func validPrice(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else {
            return nil
        }

        return value
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.nilIfEmpty
    }
}

private extension ShoppingItemStoreListing {
    var estimatedUnitPrice: Double? {
        ShoppingStoreListingPresentation.estimatedUnitPrice(for: self)
    }

    var searchableValues: [String] {
        [
            storeName,
            source,
            krogerLocationId,
            product?.brand,
            product?.name,
            product?.description,
            aisle?.display,
            aisle?.description,
            ShoppingStoreListingPresentation.priceText(for: self),
            availability?.status,
            inventory?["stockLevel"]?.stringValue,
        ].compactMap { $0 }
    }

    func withStoreFallback(_ store: ShoppingStore?) -> ShoppingItemStoreListing {
        ShoppingItemStoreListing(
            storeId: storeId ?? store?.id ?? 2,
            storeName: storeName ?? store?.name ?? "King Soopers",
            source: source,
            krogerLocationId: krogerLocationId,
            product: product,
            aisle: aisle,
            price: price,
            inventory: inventory,
            fulfillment: fulfillment,
            availability: availability,
            checkedAt: checkedAt
        )
    }
}

private extension ShoppingStoreListingPrice {
    var estimatedUnitPrice: Double? {
        let candidate = promo ?? regular
        guard let candidate, candidate.isFinite, candidate >= 0 else {
            return nil
        }

        return candidate
    }

    var displayText: String? {
        estimatedUnitPrice?.formatted(.currency(code: "USD"))
    }
}

private extension ShoppingStore {
    var isKrogerBacked: Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedName.contains("king soopers") || normalizedName.contains("kroger")
    }
}

private extension KrogerProductAisleLocation {
    var rawJSON: [String: JSONValue] {
        var values: [String: JSONValue] = [:]

        if let bayNumber {
            values["bayNumber"] = .string(bayNumber)
        }

        if let description {
            values["description"] = .string(description)
        }

        if let number {
            values["number"] = .string(number)
        }

        if let numberOfFacings {
            values["numberOfFacings"] = .string(numberOfFacings)
        }

        if let sequenceNumber {
            values["sequenceNumber"] = .string(sequenceNumber)
        }

        if let side {
            values["side"] = .string(side)
        }

        if let shelfNumber {
            values["shelfNumber"] = .string(shelfNumber)
        }

        if let shelfPositionInBay {
            values["shelfPositionInBay"] = .string(shelfPositionInBay)
        }

        return values
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var productDetailDisplayValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .capitalized
    }
}

private extension ShoppingCategory {
    var systemImage: String {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedName.contains("miscellaneous") {
            return "square.grid.2x2"
        }

        if normalizedName.contains("produce")
            || normalizedName.contains("fruit")
            || normalizedName.contains("vegetable") {
            return "carrot"
        }

        if normalizedName.contains("dairy")
            || normalizedName.contains("milk") {
            return "drop"
        }

        if normalizedName.contains("deli")
            || normalizedName.contains("prepared") {
            return "takeoutbag.and.cup.and.straw"
        }

        if normalizedName.contains("boykie")
            || normalizedName.contains("baby")
            || normalizedName.contains("kid")
            || normalizedName.contains("child") {
            return "teddybear"
        }

        if normalizedName.contains("snack") {
            return "popcorn"
        }

        if normalizedName.contains("breakfast")
            || normalizedName.contains("coffee")
            || normalizedName.contains("tea") {
            return "cup.and.saucer"
        }

        if normalizedName.contains("personal care")
            || normalizedName.contains("toiletries")
            || normalizedName.contains("hygiene") {
            return "sparkles"
        }

        if normalizedName.contains("freezer")
            || normalizedName.contains("frozen") {
            return "snowflake"
        }

        if normalizedName.contains("muti")
            || normalizedName.contains("medicine")
            || normalizedName.contains("medication")
            || normalizedName.contains("pharmacy") {
            return "pills"
        }

        if normalizedName.contains("meat")
            || normalizedName.contains("seafood") {
            return "fork.knife"
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
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedName.contains("produce")
            || normalizedName.contains("fruit")
            || normalizedName.contains("vegetable") {
            return .success
        }

        if normalizedName.contains("dairy")
            || normalizedName.contains("freezer")
            || normalizedName.contains("frozen") {
            return .accent
        }

        return .neutral
    }
}

private enum ShoppingAIPreviewScenario {
    case idle
    case running
    case unavailable
    case completedWithIssues

    var job: ShoppingStockPriceCheckSummary? {
        switch self {
        case .idle, .unavailable:
            return nil
        case .running:
            return Self.summary(
                status: .running,
                phase: .checkingStores,
                requested: 24,
                processed: 12
            )
        case .completedWithIssues:
            return Self.summary(
                status: .completedWithIssues,
                phase: .finished,
                requested: 24,
                processed: 24,
                updated: 18,
                unmatched: 4,
                failed: 2
            )
        }
    }

    var readiness: ShoppingStockPriceCheckReadiness {
        let enabled = self != .unavailable
        return ShoppingStockPriceCheckReadiness(
            ok: enabled,
            enabled: enabled,
            checks: ShoppingStockPriceCheckReadiness.Checks(
                persistence: ShoppingStockPriceCheckReadiness.Persistence(
                    ok: enabled,
                    configured: enabled,
                    code: enabled ? nil : "site_scope_unavailable"
                ),
                fixedStoreScope: ShoppingStockPriceCheckReadiness.FixedStoreScope(
                    ok: enabled,
                    targetHighlandsRanch: enabled,
                    kingSoopersWildcatReserve: enabled,
                    allowedHosts: enabled,
                    allowedMethods: enabled
                ),
                codexRuntime: ShoppingStockPriceCheckReadiness.CodexRuntime(
                    ok: enabled,
                    enabled: enabled,
                    code: enabled ? nil : "site_scope_unavailable"
                )
            )
        )
    }

    private static func summary(
        status: ShoppingStockPriceCheckStatus,
        phase: ShoppingStockPriceCheckPhase,
        requested: Int,
        processed: Int,
        updated: Int = 0,
        unmatched: Int = 0,
        failed: Int = 0
    ) -> ShoppingStockPriceCheckSummary {
        ShoppingStockPriceCheckSummary(
            ok: true,
            id: "preview-stock-price-check",
            status: status,
            phase: phase,
            requestedItemCount: requested,
            processedItemCount: processed,
            updatedItemCount: updated,
            unmatchedItemCount: unmatched,
            failedItemCount: failed,
            skippedStaleItemCount: 0,
            submittedAt: "2026-08-02T16:00:00Z",
            startedAt: "2026-08-02T16:00:01Z",
            finishedAt: status == .completedWithIssues ? "2026-08-02T16:02:00Z" : nil,
            failureCode: nil,
            message: nil
        )
    }
}

private struct ShoppingListAIPreview: View {
    let scenario: ShoppingAIPreviewScenario
    @StateObject private var viewModel: ShoppingListViewModel

    init(scenario: ShoppingAIPreviewScenario) {
        self.scenario = scenario
        let job = scenario.job
        let readiness = scenario.readiness

        _viewModel = StateObject(
            wrappedValue: ShoppingListViewModel(
                currentActorName: "Josh",
                loadShoppingList: {
                    ShoppingPreviewData.loadedResponse
                },
                lookupShoppingListItem: { name in
                    ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
                },
                createShoppingListItem: { _ in throw APIError.transport("Preview only") },
                updateShoppingListItem: { _, _ in throw APIError.transport("Preview only") },
                deleteShoppingListItem: { _, _, _ in throw APIError.transport("Preview only") },
                startShoppingStockPriceCheck: { _ in
                    guard let job else {
                        throw APIError.transport("Preview only")
                    }

                    return .accepted(job)
                },
                fetchShoppingStockPriceCheck: { _ in
                    guard let job else {
                        throw APIError.transport("Preview only")
                    }

                    return job
                },
                fetchShoppingStockPriceCheckReadiness: {
                    readiness
                }
            )
        )
    }

    var body: some View {
        ShoppingListContentView(viewModel: viewModel)
            .task {
                await viewModel.loadIfNeeded()

                if scenario == .unavailable {
                    await viewModel.refreshStockPriceCheckReadiness()
                    return
                }

                guard scenario != .idle else {
                    return
                }

                viewModel.setStockPriceCheckPollingAllowed(false)
                _ = await viewModel.startStockPriceCheck()
            }
    }
}

private enum ShoppingListReaddPreviewScenario {
    case entry
    case finding
    case resultWithUndo
    case unmatched
    case error
    case unavailable

    var run: ShoppingListReaddSummary? {
        switch self {
        case .entry, .error, .unavailable:
            return nil
        case .finding:
            return Self.summary(status: .matching)
        case .resultWithUndo:
            return Self.summary(
                status: .completed,
                operations: [
                    ShoppingListReaddOperationSummary(
                        requestIndex: 0,
                        requestedText: "2 coffees",
                        outcome: .quantityUpdated,
                        itemId: 15,
                        itemName: "Iced Coffee",
                        quantity: 2,
                        matchKind: .semantic
                    ),
                    ShoppingListReaddOperationSummary(
                        requestIndex: 1,
                        requestedText: "eggs",
                        outcome: .reAdded,
                        itemId: 16,
                        itemName: "Eggs",
                        quantity: nil,
                        matchKind: .exact
                    )
                ],
                undoAvailable: true
            )
        case .unmatched:
            return Self.summary(
                status: .completedWithIssues,
                unmatched: [ShoppingListReaddUnmatchedPhrase(requestIndex: 0, requestedText: "mango nectar")]
            )
        }
    }

    var readiness: ShoppingListReaddReadiness {
        let ready = self != .unavailable
        return ShoppingListReaddReadiness(
            ready: ready,
            matcherRuntime: ShoppingListReaddReadiness.Check(ready: ready, code: ready ? nil : "matcher_unavailable"),
            authentication: ShoppingListReaddReadiness.Check(ready: ready, code: ready ? nil : "authentication_unavailable"),
            persistence: ShoppingListReaddReadiness.Check(ready: ready, code: ready ? nil : "persistence_unavailable")
        )
    }

    private static func summary(
        status: ShoppingListReaddRunStatus,
        operations: [ShoppingListReaddOperationSummary] = [],
        unmatched: [ShoppingListReaddUnmatchedPhrase] = [],
        undoAvailable: Bool = false
    ) -> ShoppingListReaddSummary {
        ShoppingListReaddSummary(
            ok: true,
            id: "preview-readd-run",
            status: status,
            operations: operations,
            unmatched: unmatched,
            undo: ShoppingListReaddUndoAvailability(
                available: undoAvailable,
                expiresAt: undoAvailable ? "2026-08-03T12:10:00.000Z" : nil
            ),
            submittedAt: "2026-08-03T12:00:00.000Z",
            startedAt: "2026-08-03T12:00:01.000Z",
            finishedAt: status == .matching ? nil : "2026-08-03T12:00:02.000Z"
        )
    }
}

private struct ShoppingListReaddSheetPreview: View {
    let scenario: ShoppingListReaddPreviewScenario
    @StateObject private var viewModel: ShoppingListViewModel

    init(scenario: ShoppingListReaddPreviewScenario) {
        self.scenario = scenario
        let run = scenario.run
        let readiness = scenario.readiness

        _viewModel = StateObject(
            wrappedValue: ShoppingListViewModel(
                currentActorName: "Josh",
                loadShoppingList: { ShoppingPreviewData.loadedResponse },
                lookupShoppingListItem: { name in ShoppingListItemLookupResponse(ok: true, query: name, match: nil) },
                createShoppingListItem: { _ in throw APIError.transport("Preview only") },
                updateShoppingListItem: { _, _ in throw APIError.transport("Preview only") },
                deleteShoppingListItem: { _, _, _ in throw APIError.transport("Preview only") },
                startShoppingListReadd: { _ in
                    guard let run else {
                        throw APIError.transport("Preview only")
                    }
                    return .accepted(run)
                },
                fetchShoppingListReadd: { _ in
                    guard let run else {
                        throw APIError.transport("Preview only")
                    }
                    return run
                },
                undoShoppingListReadd: { _ in
                    Self.undoneRun(from: run)
                },
                fetchShoppingListReaddReadiness: { readiness }
            )
        )
    }

    var body: some View {
        ShoppingListReaddSheet(viewModel: viewModel)
            .task {
                await viewModel.loadIfNeeded()

                if scenario == .unavailable {
                    await viewModel.refreshShoppingListReaddReadiness()
                    return
                }

                guard scenario != .entry, scenario != .unavailable else {
                    return
                }

                viewModel.setShoppingListReaddPollingAllowed(false)
                _ = await viewModel.startShoppingListReadd(text: "Add 2 coffees and eggs")
            }
    }

    private static func undoneRun(from run: ShoppingListReaddSummary?) -> ShoppingListReaddSummary {
        guard let run else {
            return ShoppingListReaddSummary(
                ok: true,
                id: "preview-readd-run",
                status: .undone,
                operations: [],
                unmatched: [],
                undo: ShoppingListReaddUndoAvailability(available: false, expiresAt: nil),
                submittedAt: "2026-08-03T12:00:00.000Z",
                startedAt: "2026-08-03T12:00:01.000Z",
                finishedAt: "2026-08-03T12:00:02.000Z"
            )
        }

        return ShoppingListReaddSummary(
            ok: true,
            id: run.id,
            status: .undone,
            operations: run.operations,
            unmatched: run.unmatched,
            undo: ShoppingListReaddUndoAvailability(available: false, expiresAt: nil),
            submittedAt: run.submittedAt,
            startedAt: run.startedAt,
            finishedAt: "2026-08-03T12:00:02.000Z"
        )
    }
}

#Preview("Loaded") {
    NavigationStack {
        ShoppingListContentView(
            viewModel: ShoppingListViewModel(loadShoppingList: {
                ShoppingPreviewData.loadedResponse
            })
        )
    }
    .environmentObject(ShoppingLiveActivityCoordinator())
    .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}

#Preview("AI Idle") {
    ShoppingListAIPreview(scenario: .idle)
        .environmentObject(ShoppingLiveActivityCoordinator())
        .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}

#Preview("AI Running") {
    ShoppingListAIPreview(scenario: .running)
        .environmentObject(ShoppingLiveActivityCoordinator())
        .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}

#Preview("AI Unavailable") {
    ShoppingListAIPreview(scenario: .unavailable)
        .environmentObject(ShoppingLiveActivityCoordinator())
        .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}

#Preview("AI Completed With Issues") {
    ShoppingListAIPreview(scenario: .completedWithIssues)
        .environmentObject(ShoppingLiveActivityCoordinator())
        .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}

#Preview("AI Compact Screen") {
    ShoppingListAIPreview(scenario: .running)
        .frame(width: 320, height: 640)
        .environmentObject(ShoppingLiveActivityCoordinator())
        .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}

#Preview("AI Text Entry") {
    ShoppingListReaddSheetPreview(scenario: .entry)
}

#Preview("AI Finding Items") {
    ShoppingListReaddSheetPreview(scenario: .finding)
}

#Preview("AI Re-add Result With Undo") {
    ShoppingListReaddSheetPreview(scenario: .resultWithUndo)
}

#Preview("AI Re-add Unmatched") {
    ShoppingListReaddSheetPreview(scenario: .unmatched)
}

#Preview("AI Re-add Error") {
    ShoppingListReaddSheetPreview(scenario: .error)
}

#Preview("AI Re-add Unavailable") {
    ShoppingListReaddSheetPreview(scenario: .unavailable)
}

#Preview("AI Re-add Compact") {
    ShoppingListReaddSheetPreview(scenario: .resultWithUndo)
        .frame(width: 320, height: 640)
}

#Preview("AI Re-add Dynamic Type") {
    ShoppingListReaddSheetPreview(scenario: .resultWithUndo)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Empty") {
    NavigationStack {
        ShoppingListContentView(
            viewModel: ShoppingListViewModel(loadShoppingList: {
                ShoppingPreviewData.emptyResponse
            })
        )
    }
    .environmentObject(ShoppingLiveActivityCoordinator())
    .environmentObject(PushRegistrationViewModel(service: NotificationService.shared))
}
