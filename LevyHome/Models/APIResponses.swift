import Foundation

struct EventsResponse: Codable, Equatable {
    let ok: Bool
    let events: [LevyHomeEvent]
}

struct HomeOverviewResponse: Codable, Equatable {
    let ok: Bool
    let overview: HomeOverview
}

struct QuickActionsResponse: Codable, Equatable {
    let ok: Bool
    let actions: [QuickAction]
    let lightGroups: [LightActionGroup]?
}

struct QuickActionResponse: Codable, Equatable {
    let ok: Bool
    let result: QuickActionResult
}

struct UsersResponse: Codable, Equatable {
    let ok: Bool
    let users: [LevyHomeUser]
    let generatedAt: String?
}

struct LevyHomeUser: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String
    let mobileDevice: String?
    let lastLogin: String?

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    var initials: String {
        let firstInitial = firstName.first.map(String.init) ?? ""
        let lastInitial = lastName.first.map(String.init) ?? ""

        return "\(firstInitial)\(lastInitial)".uppercased()
    }
}

struct ToDoLocationsResponse: Codable, Equatable {
    let ok: Bool
    let locations: [ToDoLocation]
    let generatedAt: String?
}

struct ToDoLocation: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let name: String
    let address: String?
    let mapkitTitle: String?
    let mapkitSubtitle: String?
    let latitude: Double?
    let longitude: Double?
    let createdBy: Int?
    let createdDate: String
    let lastUsedDate: String?
    let useCount: Int
    let isActive: Bool
    let favoritedBy: [Int]
}

struct CreateToDoLocationRequest: Codable, Equatable {
    let name: String
    let address: String?
    let mapkitTitle: String?
    let mapkitSubtitle: String?
    let latitude: Double?
    let longitude: Double?
    let createdBy: Int?
    let favoritedBy: [Int]
}

struct ToDoLocationMutationResponse: Codable, Equatable {
    let ok: Bool
    let location: ToDoLocation
    let generatedAt: String?
}

struct ShoppingListResponse: Codable, Equatable {
    let ok: Bool
    let items: [ShoppingListItem]
    let stores: [ShoppingStore]
    let categories: [ShoppingCategory]
    let generatedAt: String?
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
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }

        return nil
    }
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
    let mutationId: String
    let generatedAt: String?
}

struct DeleteShoppingListItemResponse: Codable, Equatable {
    let ok: Bool
    let itemId: Int
    let item: ShoppingListItem
    let mutationId: String
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

struct NotificationPreferencesResponse: Codable, Equatable {
    let ok: Bool
    let preferences: [NotificationPreference]
    let syncedAt: String?
}

struct RegisteredDevice: Codable, Equatable, Identifiable {
    let id: String?
    let platform: DevicePlatform?
    let provider: PushProvider?
    let environment: APNsEnvironment?
    let registeredAt: String?
    let lastSeenAt: String?
}

struct RegisterDeviceResponse: Codable, Equatable {
    let ok: Bool
    let registeredDeviceCount: Int
    let device: RegisteredDevice?
}

struct TestPushResponse: Codable, Equatable {
    let ok: Bool
    let message: String
    let registeredDeviceCount: Int
    let sentNotificationCount: Int?
    let sentTicketCount: Int?
    let invalidTokenCount: Int?
    let provider: PushProvider?
}

struct HealthResponse: Codable, Equatable {
    let ok: Bool
    let service: String?
    let registeredDeviceCount: Int?
    let recentEventCount: Int?
    let uptimeSeconds: Double?
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
