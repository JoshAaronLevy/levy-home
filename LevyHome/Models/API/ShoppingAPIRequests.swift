import Foundation

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
