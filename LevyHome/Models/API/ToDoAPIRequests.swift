import Foundation

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
