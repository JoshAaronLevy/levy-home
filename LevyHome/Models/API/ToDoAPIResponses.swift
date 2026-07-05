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

struct ToDoLocationMutationResponse: Codable, Equatable {
    let ok: Bool
    let location: ToDoLocation
    let generatedAt: String?
}

enum ToDoItemStatus: String, Codable, Equatable, Hashable {
    case open
    case completed
    case canceled
}

enum ToDoItemRecurring: String, Codable, Equatable, Hashable {
    case daily
    case weekly
    case monthly
    case quarterly
}

struct ToDoCategory: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let name: String?
    let updatedAt: String?
}

struct ToDoItem: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let status: ToDoItemStatus
    let locationIds: [Int]
    let locationDisplayText: String
    let date: String?
    let recurring: ToDoItemRecurring?
    let createdBy: Int?
    let createdDate: String?
}

struct ToDoListResponse: Codable, Equatable {
    let ok: Bool
    let items: [ToDoItem]
    let categories: [ToDoCategory]
    let locations: [ToDoLocation]
    let generatedAt: String?
}

struct ToDoListMutationResponse: Codable, Equatable {
    let ok: Bool
    let item: ToDoItem
    let mutationId: String
    let generatedAt: String?
    let push: PushDeliveryStatus?
}

struct DeleteToDoItemResponse: Codable, Equatable {
    let ok: Bool
    let itemId: Int
    let item: ToDoItem
    let mutationId: String
    let generatedAt: String?
    let push: PushDeliveryStatus?
}
