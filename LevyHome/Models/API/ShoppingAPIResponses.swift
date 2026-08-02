struct ShoppingListResponse: Codable, Equatable {
    let ok: Bool
    let items: [ShoppingListItem]
    let stores: [ShoppingStore]
    let categories: [ShoppingCategory]
    let activeTrip: ShoppingTrip?
    let generatedAt: String?

    init(
        ok: Bool,
        items: [ShoppingListItem],
        stores: [ShoppingStore],
        categories: [ShoppingCategory],
        activeTrip: ShoppingTrip? = nil,
        generatedAt: String?
    ) {
        self.ok = ok
        self.items = items
        self.stores = stores
        self.categories = categories
        self.activeTrip = activeTrip
        self.generatedAt = generatedAt
    }
}

struct ShoppingListItem: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let brand: String?
    let quantity: Int
    let notes: String?
    let purchased: Bool
    let created: String?
    let updated: String?
    let version: Int?
    let categoryId: Int?
    let image: String?
    let storeListings: [ShoppingItemStoreListing]

    init(
        id: Int,
        name: String,
        brand: String?,
        quantity: Int,
        notes: String?,
        purchased: Bool,
        created: String?,
        updated: String?,
        version: Int? = nil,
        categoryId: Int?,
        image: String? = nil,
        storeListings: [ShoppingItemStoreListing] = []
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.notes = notes
        self.purchased = purchased
        self.created = created
        self.updated = updated
        self.version = version
        self.categoryId = categoryId
        self.image = image
        self.storeListings = storeListings
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case brand
        case quantity
        case notes
        case purchased
        case created
        case updated
        case createdAt
        case updatedAt
        case version
        case storeIds
        case categoryId
        case image
        case storeListings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyStoreIds = (try? container.decodeIfPresent([Int].self, forKey: .storeIds)) ?? []

        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        purchased = try container.decodeIfPresent(Bool.self, forKey: .purchased) ?? false
        created = try container.decodeIfPresent(String.self, forKey: .created)
            ?? container.decodeIfPresent(String.self, forKey: .createdAt)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
            ?? container.decodeIfPresent(String.self, forKey: .updatedAt)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        categoryId = try container.decodeIfPresent(Int.self, forKey: .categoryId)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        storeListings = try container.decodeIfPresent([ShoppingItemStoreListing].self, forKey: .storeListings)
            ?? legacyStoreIds.map { ShoppingItemStoreListing(storeId: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encode(quantity, forKey: .quantity)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(purchased, forKey: .purchased)
        try container.encodeIfPresent(created, forKey: .created)
        try container.encodeIfPresent(updated, forKey: .updated)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(storeListings, forKey: .storeListings)
    }
}

struct ShoppingItemStoreListing: Codable, Equatable, Identifiable {
    let storeId: Int?
    let storeName: String?
    let source: String?
    let selectedStoreAddress: String?
    let krogerLocationId: String?
    let product: ShoppingStoreListingProduct?
    let aisle: ShoppingStoreListingAisle?
    let price: ShoppingStoreListingPrice?
    let inventory: [String: JSONValue]?
    let fulfillment: [String: JSONValue]?
    let availability: ShoppingStoreListingAvailability?
    let checkedAt: String?

    var id: String {
        if let storeId {
            return "store-\(storeId)"
        }

        if let storeName {
            return "store-\(storeName.lowercased())"
        }

        if let productId = product?.productId {
            return "product-\(productId)"
        }

        return [
            source,
            krogerLocationId,
            product?.upc,
            product?.name
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: "-")
    }

    init(
        storeId: Int? = nil,
        storeName: String? = nil,
        source: String? = nil,
        selectedStoreAddress: String? = nil,
        krogerLocationId: String? = nil,
        product: ShoppingStoreListingProduct? = nil,
        aisle: ShoppingStoreListingAisle? = nil,
        price: ShoppingStoreListingPrice? = nil,
        inventory: [String: JSONValue]? = nil,
        fulfillment: [String: JSONValue]? = nil,
        availability: ShoppingStoreListingAvailability? = nil,
        checkedAt: String? = nil
    ) {
        self.storeId = storeId
        self.storeName = storeName
        self.source = source
        self.selectedStoreAddress = selectedStoreAddress
        self.krogerLocationId = krogerLocationId
        self.product = product
        self.aisle = aisle
        self.price = price
        self.inventory = inventory
        self.fulfillment = fulfillment
        self.availability = availability
        self.checkedAt = checkedAt
    }
}

struct ShoppingStoreListingProduct: Codable, Equatable {
    let productId: String?
    let upc: String?
    let productPageURI: String?
    let brand: String?
    let name: String?
    let description: String?
    let image: String?
}

struct ShoppingStoreListingAisle: Codable, Equatable {
    let display: String?
    let description: String?
    let number: String?
    let shelfNumber: String?
    let raw: [String: JSONValue]?
}

struct ShoppingStoreListingPrice: Codable, Equatable {
    let regular: Double?
    let promo: Double?
}

struct ShoppingStoreListingAvailability: Codable, Equatable {
    let status: String?
    let checkedAt: String?
    let matchStatus: String?

    init(status: String? = nil, checkedAt: String? = nil, matchStatus: String? = nil) {
        self.status = status
        self.checkedAt = checkedAt
        self.matchStatus = matchStatus
    }

    var normalizedStatus: ShoppingStockAvailabilityStatus {
        ShoppingStockAvailabilityStatus(rawValue: status ?? "") ?? .unknown
    }
}

enum ShoppingStockAvailabilityStatus: String, Codable, Equatable {
    case inStock = "in_stock"
    case lowStock = "low_stock"
    case outOfStock = "out_of_stock"
    case unknown
}

enum ShoppingStockPriceCheckStatus: Equatable, Codable {
    case queued
    case running
    case completed
    case completedWithIssues
    case failed
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "queued": self = .queued
        case "running": self = .running
        case "completed": self = .completed
        case "completed_with_issues": self = .completedWithIssues
        case "failed": self = .failed
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let value: String
        switch self {
        case .queued: value = "queued"
        case .running: value = "running"
        case .completed: value = "completed"
        case .completedWithIssues: value = "completed_with_issues"
        case .failed: value = "failed"
        case .unknown(let unknown): value = unknown
        }
        try container.encode(value)
    }
}

enum ShoppingStockPriceCheckPhase: Equatable, Codable {
    case preparing
    case checkingStores
    case matchingProducts
    case applyingUpdates
    case finished
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "preparing": self = .preparing
        case "checking_stores": self = .checkingStores
        case "matching_products": self = .matchingProducts
        case "applying_updates": self = .applyingUpdates
        case "finished": self = .finished
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let value: String
        switch self {
        case .preparing: value = "preparing"
        case .checkingStores: value = "checking_stores"
        case .matchingProducts: value = "matching_products"
        case .applyingUpdates: value = "applying_updates"
        case .finished: value = "finished"
        case .unknown(let unknown): value = unknown
        }
        try container.encode(value)
    }
}

struct ShoppingStockPriceCheckSummary: Codable, Equatable {
    let ok: Bool
    let id: String
    let status: ShoppingStockPriceCheckStatus
    let phase: ShoppingStockPriceCheckPhase
    let requestedItemCount: Int
    let processedItemCount: Int
    let updatedItemCount: Int
    let unmatchedItemCount: Int
    let failedItemCount: Int
    let skippedStaleItemCount: Int
    let submittedAt: String
    let startedAt: String?
    let finishedAt: String?
    let failureCode: String?
    let message: String?
}

struct ShoppingListItemLookupResponse: Codable, Equatable {
    let ok: Bool
    let query: String
    let match: ShoppingListItem?
}

struct KrogerProductDiagnosticResponse: Codable, Equatable {
    let ok: Bool
    let query: String
    let generatedAt: String?
    let stage: String?
    let outputFilePath: String?
    let normalizedOutputFilePath: String?
    let tokenStatusCode: Int?
    let productStatusCode: Int?
    let products: [KrogerProduct]
    let error: String?
}

struct KrogerProductSearchResponse: Codable, Equatable {
    let ok: Bool
    let query: String
    let generatedAt: String?
    let productStatusCode: Int?
    let products: [KrogerProduct]
    let error: String?
}

struct KrogerProduct: Codable, Equatable {
    let productId: String?
    let upc: String?
    let productPageURI: String?
    let aisles: [KrogerProductAisleLocation]
    let brand: String?
    let name: String?
    let description: String?
    let image: String?
    let storeListings: [ShoppingItemStoreListing]

    init(
        productId: String?,
        upc: String?,
        productPageURI: String?,
        aisles: [KrogerProductAisleLocation],
        brand: String?,
        name: String?,
        description: String?,
        image: String?,
        storeListings: [ShoppingItemStoreListing] = []
    ) {
        self.productId = productId
        self.upc = upc
        self.productPageURI = productPageURI
        self.aisles = aisles
        self.brand = brand
        self.name = name
        self.description = description
        self.image = image
        self.storeListings = storeListings
    }

    private enum CodingKeys: String, CodingKey {
        case productId
        case upc
        case productPageURI
        case aisles
        case brand
        case name
        case description
        case image
        case storeListings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        productId = try container.decodeIfPresent(String.self, forKey: .productId)
        upc = try container.decodeIfPresent(String.self, forKey: .upc)
        productPageURI = try container.decodeIfPresent(String.self, forKey: .productPageURI)
        aisles = try container.decodeIfPresent([KrogerProductAisleLocation].self, forKey: .aisles) ?? []
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        storeListings = try container.decodeIfPresent([ShoppingItemStoreListing].self, forKey: .storeListings) ?? []
    }
}

struct KrogerProductAisleLocation: Codable, Equatable {
    let bayNumber: String?
    let description: String?
    let number: String?
    let numberOfFacings: String?
    let sequenceNumber: String?
    let side: String?
    let shelfNumber: String?
    let shelfPositionInBay: String?

    init(
        bayNumber: String? = nil,
        description: String? = nil,
        number: String? = nil,
        numberOfFacings: String? = nil,
        sequenceNumber: String? = nil,
        side: String? = nil,
        shelfNumber: String? = nil,
        shelfPositionInBay: String? = nil
    ) {
        self.bayNumber = bayNumber
        self.description = description
        self.number = number
        self.numberOfFacings = numberOfFacings
        self.sequenceNumber = sequenceNumber
        self.side = side
        self.shelfNumber = shelfNumber
        self.shelfPositionInBay = shelfPositionInBay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        bayNumber = try container.decodeFlexibleStringIfPresent(forKey: .bayNumber)
        description = try container.decodeFlexibleStringIfPresent(forKey: .description)
        number = try container.decodeFlexibleStringIfPresent(forKey: .number)
        numberOfFacings = try container.decodeFlexibleStringIfPresent(forKey: .numberOfFacings)
        sequenceNumber = try container.decodeFlexibleStringIfPresent(forKey: .sequenceNumber)
        side = try container.decodeFlexibleStringIfPresent(forKey: .side)
        shelfNumber = try container.decodeFlexibleStringIfPresent(forKey: .shelfNumber)
        shelfPositionInBay = try container.decodeFlexibleStringIfPresent(forKey: .shelfPositionInBay)
    }
}

struct ShoppingListMutationResponse: Codable, Equatable {
    let ok: Bool
    let item: ShoppingListItem
    let activeTrip: ShoppingTrip?
    let mutationId: String
    let generatedAt: String?
    let push: PushDeliveryStatus?

    init(
        ok: Bool,
        item: ShoppingListItem,
        activeTrip: ShoppingTrip? = nil,
        mutationId: String,
        generatedAt: String?,
        push: PushDeliveryStatus? = nil
    ) {
        self.ok = ok
        self.item = item
        self.activeTrip = activeTrip
        self.mutationId = mutationId
        self.generatedAt = generatedAt
        self.push = push
    }
}

struct DeleteShoppingListItemResponse: Codable, Equatable {
    let ok: Bool
    let itemId: Int
    let item: ShoppingListItem
    let activeTrip: ShoppingTrip?
    let mutationId: String
    let generatedAt: String?
    let push: PushDeliveryStatus?

    init(
        ok: Bool,
        itemId: Int,
        item: ShoppingListItem,
        activeTrip: ShoppingTrip? = nil,
        mutationId: String,
        generatedAt: String?,
        push: PushDeliveryStatus? = nil
    ) {
        self.ok = ok
        self.itemId = itemId
        self.item = item
        self.activeTrip = activeTrip
        self.mutationId = mutationId
        self.generatedAt = generatedAt
        self.push = push
    }
}

struct ShoppingTrip: Codable, Equatable, Identifiable {
    let id: String
    let status: String
    let startedBy: String
    let startedAt: String
    let endedBy: String?
    let endedAt: String?
    let pickedUpCount: Int
    let remainingCount: Int
    let totalItemCount: Int
    let estimatedTotalCents: Int
    let pricedPickedItemCount: Int
    let unpricedPickedItemCount: Int
    let currencyCode: String
    let version: Int
    let activityUpdatedAtEpochSeconds: Int?
}

struct ShoppingActiveTripResponse: Codable, Equatable {
    let ok: Bool
    let activeTrip: ShoppingTrip?
    let generatedAt: String?
}

struct ShoppingTripMutationResponse: Codable, Equatable {
    let ok: Bool
    let trip: ShoppingTrip
    let activeTrip: ShoppingTrip?
    let mutationId: String
    let displayDisposition: ShoppingTripDisplayDisposition?
    let generatedAt: String?
}

struct ShoppingTripDisplayDisposition: Codable, Equatable {
    let tripId: String
    let pushDeviceId: String
    let resident: String
    let kind: String
    let remoteStartCount: Int

    var startsLocally: Bool {
        kind == "start_locally"
    }
}

struct ClaimShoppingTripDisplayResponse: Codable, Equatable {
    let ok: Bool
    let displayDisposition: ShoppingTripDisplayDisposition
    let generatedAt: String?
}

struct ShoppingLiveActivityRegistration: Codable, Equatable, Identifiable {
    let id: String
    let pushDeviceId: String
    let resident: String
    let environment: APNsEnvironment
    let tokenType: String
    let tripId: String?
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
}

struct ShoppingLiveActivityRegistrationResponse: Codable, Equatable {
    let ok: Bool
    let registration: ShoppingLiveActivityRegistration
    let generatedAt: String?
}

struct ShoppingLiveActivityDebugDeliveryResponse: Codable, Equatable {
    let ok: Bool
    let trip: ShoppingTrip
    let queuedDeliveryCount: Int
    let deliveryIds: [String]
    let generatedAt: String?
}

struct ShoppingStore: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let name: String
    let logo: String?
}

struct ShoppingCategory: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let name: String
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return String(doubleValue)
        }

        return nil
    }
}
