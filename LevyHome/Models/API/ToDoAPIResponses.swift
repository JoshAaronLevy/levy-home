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
    let alerts: [JSONValue]
    let createdBy: Int?
    let createdDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case locationIds
        case locationDisplayText
        case date
        case recurring
        case alerts
        case createdBy
        case createdDate
    }

    init(
        id: Int,
        name: String,
        status: ToDoItemStatus,
        locationIds: [Int],
        locationDisplayText: String,
        date: String? = nil,
        recurring: ToDoItemRecurring? = nil,
        alerts: [JSONValue] = [],
        createdBy: Int? = nil,
        createdDate: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.locationIds = locationIds
        self.locationDisplayText = locationDisplayText
        self.date = date
        self.recurring = recurring
        self.alerts = alerts
        self.createdBy = createdBy
        self.createdDate = createdDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(ToDoItemStatus.self, forKey: .status)
        locationIds = try container.decode([Int].self, forKey: .locationIds)
        locationDisplayText = try container.decode(String.self, forKey: .locationDisplayText)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        recurring = try container.decodeIfPresent(ToDoItemRecurring.self, forKey: .recurring)
        alerts = try container.decodeIfPresent([JSONValue].self, forKey: .alerts) ?? []
        createdBy = try container.decodeIfPresent(Int.self, forKey: .createdBy)
        createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
    }
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
