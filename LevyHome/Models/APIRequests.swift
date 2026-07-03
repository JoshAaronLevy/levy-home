import Foundation

struct FetchEventsRequest: Encodable, Equatable {
    let limit: Int?
}

enum ShoppingListNullableValue<Value: Encodable & Equatable>: Encodable, Equatable {
    case value(Value)
    case null

    func encode(to encoder: Encoder) throws {
        switch self {
        case .value(let value):
            try value.encode(to: encoder)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

struct CreateShoppingListItemRequest: Encodable, Equatable {
    let name: String
    let brand: String?
    let quantity: Int?
    let notes: String?
    let purchased: Bool?
    let categoryId: Int?
    let image: String?
    let storeListings: [ShoppingItemStoreListing]?
    let actor: String?
    let mutationId: String

    init(
        name: String,
        brand: String? = nil,
        quantity: Int? = nil,
        notes: String? = nil,
        purchased: Bool? = nil,
        categoryId: Int? = nil,
        image: String? = nil,
        storeListings: [ShoppingItemStoreListing]? = nil,
        actor: String? = nil,
        mutationId: String = UUID().uuidString
    ) {
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.notes = notes
        self.purchased = purchased
        self.categoryId = categoryId
        self.image = image
        self.storeListings = storeListings
        self.actor = actor
        self.mutationId = mutationId
    }
}

struct UpdateShoppingListItemRequest: Encodable, Equatable {
    let name: String?
    let brand: ShoppingListNullableValue<String>?
    let quantity: Int?
    let notes: ShoppingListNullableValue<String>?
    let purchased: Bool?
    let categoryId: ShoppingListNullableValue<Int>?
    let image: ShoppingListNullableValue<String>?
    let storeListings: [ShoppingItemStoreListing]?
    let actor: String?
    let mutationId: String

    init(
        name: String? = nil,
        brand: ShoppingListNullableValue<String>? = nil,
        quantity: Int? = nil,
        notes: ShoppingListNullableValue<String>? = nil,
        purchased: Bool? = nil,
        categoryId: ShoppingListNullableValue<Int>? = nil,
        image: ShoppingListNullableValue<String>? = nil,
        storeListings: [ShoppingItemStoreListing]? = nil,
        actor: String? = nil,
        mutationId: String = UUID().uuidString
    ) {
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.notes = notes
        self.purchased = purchased
        self.categoryId = categoryId
        self.image = image
        self.storeListings = storeListings
        self.actor = actor
        self.mutationId = mutationId
    }
}

struct DeleteShoppingListItemRequest: Encodable, Equatable {
    let actor: String?
    let mutationId: String

    init(actor: String? = nil, mutationId: String = UUID().uuidString) {
        self.actor = actor
        self.mutationId = mutationId
    }
}

struct CreateToDoItemRequest: Encodable, Equatable {
    let name: String
    let status: ToDoItemStatus?
    let locationIds: [Int]?
    let date: String?
    let recurring: ToDoItemRecurring?
    let createdBy: Int?
    let actor: String?
    let mutationId: String

    init(
        name: String,
        status: ToDoItemStatus? = nil,
        locationIds: [Int]? = nil,
        date: String? = nil,
        recurring: ToDoItemRecurring? = nil,
        createdBy: Int? = nil,
        actor: String? = nil,
        mutationId: String = UUID().uuidString
    ) {
        self.name = name
        self.status = status
        self.locationIds = locationIds
        self.date = date
        self.recurring = recurring
        self.createdBy = createdBy
        self.actor = actor
        self.mutationId = mutationId
    }
}

struct UpdateToDoItemRequest: Encodable, Equatable {
    let name: String?
    let status: ToDoItemStatus?
    let locationIds: [Int]?
    let date: ShoppingListNullableValue<String>?
    let recurring: ShoppingListNullableValue<ToDoItemRecurring>?
    let createdBy: ShoppingListNullableValue<Int>?
    let actor: String?
    let mutationId: String

    init(
        name: String? = nil,
        status: ToDoItemStatus? = nil,
        locationIds: [Int]? = nil,
        date: ShoppingListNullableValue<String>? = nil,
        recurring: ShoppingListNullableValue<ToDoItemRecurring>? = nil,
        createdBy: ShoppingListNullableValue<Int>? = nil,
        actor: String? = nil,
        mutationId: String = UUID().uuidString
    ) {
        self.name = name
        self.status = status
        self.locationIds = locationIds
        self.date = date
        self.recurring = recurring
        self.createdBy = createdBy
        self.actor = actor
        self.mutationId = mutationId
    }
}

struct DeleteToDoItemRequest: Encodable, Equatable {
    let actor: String?
    let mutationId: String

    init(actor: String? = nil, mutationId: String = UUID().uuidString) {
        self.actor = actor
        self.mutationId = mutationId
    }
}

enum QuickActionRequest: Encodable, Equatable {
    case openGarage
    case closeGarage
    case turnOffAllLights
    case turnOffLightGroup(groupId: String)

    private enum CodingKeys: String, CodingKey {
        case actionId
        case groupId
    }

    var actionId: QuickActionID {
        switch self {
        case .openGarage:
            return .openGarage
        case .closeGarage:
            return .closeGarage
        case .turnOffAllLights:
            return .turnOffAllLights
        case .turnOffLightGroup:
            return .turnOffLightGroup
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionId, forKey: .actionId)

        if case .turnOffLightGroup(let groupId) = self {
            try container.encode(groupId, forKey: .groupId)
        }
    }
}

struct NotificationPreferenceUpdate: Codable, Equatable {
    let category: NotificationPreferenceCategory
    let isEnabled: Bool
}

struct NotificationPreferencesUpdateRequest: Codable, Equatable {
    let preferences: [NotificationPreferenceUpdate]
    let deviceToken: String?
    let provider: PushProvider?
    let environment: APNsEnvironment?

    init(
        preferences: [NotificationPreferenceUpdate],
        deviceToken: String? = nil,
        provider: PushProvider? = nil,
        environment: APNsEnvironment? = nil
    ) {
        self.preferences = preferences
        self.deviceToken = deviceToken
        self.provider = provider
        self.environment = environment
    }
}

enum DevicePlatform: String, Codable, Equatable {
    case iOS = "ios"
}

enum PushProvider: String, Codable, Equatable {
    case apns
}

enum APNsEnvironment: String, Codable, Equatable {
    case sandbox
    case production
}

struct RegisterDeviceRequest: Codable, Equatable {
    let token: String
    let platform: DevicePlatform
    let provider: PushProvider
    let environment: APNsEnvironment
    let appVersion: String?
    let deviceName: String?
}

struct TestPushRequest: Codable, Equatable {
    let title: String?
    let body: String?
}
