import Foundation

enum ShoppingListSnapshotRequiredReason: Equatable {
    case connected
    case missedMessages
    case serverRestart
    case unknown(String)

    var rawValue: String {
        switch self {
        case .connected:
            return "connected"
        case .missedMessages:
            return "missed_messages"
        case .serverRestart:
            return "server_restart"
        case .unknown(let value):
            return value
        }
    }
}

extension ShoppingListSnapshotRequiredReason: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "connected":
            self = .connected
        case "missed_messages":
            self = .missedMessages
        case "server_restart":
            self = .serverRestart
        default:
            self = .unknown(rawValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ShoppingListLiveMessage: Decodable, Equatable {
    case hello(connectionId: String, serverTime: String)
    case presenceChanged(viewers: [ShoppingListViewerPresence], serverTime: String)
    case snapshotRequired(reason: ShoppingListSnapshotRequiredReason, serverTime: String)
    case itemCreated(item: ShoppingListItem, mutationId: String, serverTime: String)
    case itemUpdated(item: ShoppingListItem, mutationId: String, serverTime: String)
    case itemDeleted(itemId: Int, mutationId: String, serverTime: String)
    case storesChanged(stores: [ShoppingStore], mutationId: String, serverTime: String)
    case categoriesChanged(categories: [ShoppingCategory], mutationId: String, serverTime: String)
    case tripStarted(trip: ShoppingTrip, mutationId: String, serverTime: String)
    case tripUpdated(trip: ShoppingTrip, mutationId: String, serverTime: String)
    case tripEnded(trip: ShoppingTrip, mutationId: String, serverTime: String)
    case unknown(type: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case connectionId
        case serverTime
        case viewers
        case reason
        case item
        case mutationId
        case itemId
        case stores
        case categories
        case trip
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)

        switch type {
        case "hello":
            self = .hello(
                connectionId: try container.decode(String.self, forKey: .connectionId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "presence_changed":
            self = .presenceChanged(
                viewers: try container.decode([ShoppingListViewerPresence].self, forKey: .viewers),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "snapshot_required":
            self = .snapshotRequired(
                reason: try container.decode(ShoppingListSnapshotRequiredReason.self, forKey: .reason),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "item_created":
            self = .itemCreated(
                item: try container.decode(ShoppingListItem.self, forKey: .item),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "item_updated":
            self = .itemUpdated(
                item: try container.decode(ShoppingListItem.self, forKey: .item),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "item_deleted":
            self = .itemDeleted(
                itemId: try container.decode(Int.self, forKey: .itemId),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "stores_changed":
            self = .storesChanged(
                stores: try container.decode([ShoppingStore].self, forKey: .stores),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "categories_changed":
            self = .categoriesChanged(
                categories: try container.decode([ShoppingCategory].self, forKey: .categories),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "trip_started":
            self = .tripStarted(
                trip: try container.decode(ShoppingTrip.self, forKey: .trip),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "trip_updated":
            self = .tripUpdated(
                trip: try container.decode(ShoppingTrip.self, forKey: .trip),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "trip_ended":
            self = .tripEnded(
                trip: try container.decode(ShoppingTrip.self, forKey: .trip),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        default:
            self = .unknown(type: type)
        }
    }
}

enum ShoppingListLiveClientMessage: Encodable, Equatable {
    case subscribe(ShoppingListViewerIdentity)
    case presencePing(viewerId: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case viewerId
        case displayName
        case deviceName
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .subscribe(let identity):
            try container.encode("subscribe", forKey: .type)
            try container.encode(identity.viewerId, forKey: .viewerId)
            try container.encode(identity.displayName, forKey: .displayName)
            try container.encodeIfPresent(identity.deviceName, forKey: .deviceName)
        case .presencePing(let viewerId):
            try container.encode("presence_ping", forKey: .type)
            try container.encode(viewerId, forKey: .viewerId)
        }
    }
}
