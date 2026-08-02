import Foundation

struct StartShoppingStockPriceCheckRequest: Encodable, Equatable {
    let actor: String?
    let mutationId: String

    init(actor: String? = nil, mutationId: String = UUID().uuidString) {
        self.actor = actor
        self.mutationId = mutationId
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

    var hasMutableFields: Bool {
        name != nil
            || brand != nil
            || quantity != nil
            || notes != nil
            || purchased != nil
            || categoryId != nil
            || image != nil
            || storeListings != nil
    }

    func isReflected(in item: ShoppingListItem) -> Bool {
        if let name, item.name != name {
            return false
        }

        if let brand, !brand.matches(item.brand) {
            return false
        }

        if let quantity, item.quantity != quantity {
            return false
        }

        if let notes, !notes.matches(item.notes) {
            return false
        }

        if let purchased, item.purchased != purchased {
            return false
        }

        if let categoryId, !categoryId.matches(item.categoryId) {
            return false
        }

        if let image, !image.matches(item.image) {
            return false
        }

        if let storeListings, item.storeListings != storeListings {
            return false
        }

        return true
    }
}

private extension ShoppingListNullableValue where Value: Equatable {
    func matches(_ value: Value?) -> Bool {
        switch self {
        case .value(let expected):
            return value == expected
        case .null:
            return value == nil
        }
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

struct StartShoppingTripRequest: Encodable, Equatable {
    let actor: String
    let mutationId: String
    let originatingPushDeviceId: String?

    init(
        actor: String,
        mutationId: String = UUID().uuidString,
        originatingPushDeviceId: String? = nil
    ) {
        self.actor = actor
        self.mutationId = mutationId
        self.originatingPushDeviceId = originatingPushDeviceId
    }
}

struct ClaimShoppingTripDisplayRequest: Encodable, Equatable {
    let actor: String
    let pushDeviceId: String
}

struct EndShoppingTripRequest: Encodable, Equatable {
    let tripId: String
    let actor: String
    let mutationId: String
    let summaryRecipient: String?

    init(
        tripId: String,
        actor: String,
        mutationId: String = UUID().uuidString,
        summaryRecipient: String? = nil
    ) {
        self.tripId = tripId
        self.actor = actor
        self.mutationId = mutationId
        self.summaryRecipient = summaryRecipient
    }
}

struct ShoppingLiveActivityRegistrationRequest: Encodable, Equatable {
    let pushDeviceId: String
    let resident: String
    let environment: APNsEnvironment
    let tokenType: String
    let token: String
    let tripId: String?
}
