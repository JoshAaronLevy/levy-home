import Foundation

extension ResidentIdentity {
    var toDoListViewerId: String {
        switch self {
        case .josh:
            return "josh"
        case .mallory:
            return "mallory"
        }
    }

    var toDoUserId: Int {
        switch self {
        case .josh:
            return 1
        case .mallory:
            return 2
        }
    }
}

struct ToDoListViewerIdentity: Equatable {
    let viewerId: String
    let displayName: String
    let deviceName: String?

    init(viewerId: String, displayName: String, deviceName: String? = nil) {
        self.viewerId = viewerId
        self.displayName = displayName
        self.deviceName = deviceName.flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct ToDoListViewerPresence: Codable, Equatable, Identifiable {
    let viewerId: String
    let displayName: String
    let connectionId: String
    let deviceName: String?
    let lastSeenAt: String

    var id: String {
        viewerId
    }
}

enum ToDoListSnapshotRequiredReason: Equatable {
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

extension ToDoListSnapshotRequiredReason: Codable {
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

enum ToDoListLiveMessage: Decodable, Equatable {
    case hello(connectionId: String, serverTime: String)
    case presenceChanged(viewers: [ToDoListViewerPresence], serverTime: String)
    case snapshotRequired(reason: ToDoListSnapshotRequiredReason, serverTime: String)
    case itemCreated(item: ToDoItem, mutationId: String, serverTime: String)
    case itemUpdated(item: ToDoItem, mutationId: String, serverTime: String)
    case itemDeleted(itemId: Int, mutationId: String, serverTime: String)
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
                viewers: try container.decode([ToDoListViewerPresence].self, forKey: .viewers),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "snapshot_required":
            self = .snapshotRequired(
                reason: try container.decode(ToDoListSnapshotRequiredReason.self, forKey: .reason),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "item_created":
            self = .itemCreated(
                item: try container.decode(ToDoItem.self, forKey: .item),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "item_updated":
            self = .itemUpdated(
                item: try container.decode(ToDoItem.self, forKey: .item),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        case "item_deleted":
            self = .itemDeleted(
                itemId: try container.decode(Int.self, forKey: .itemId),
                mutationId: try container.decode(String.self, forKey: .mutationId),
                serverTime: try container.decode(String.self, forKey: .serverTime)
            )
        default:
            self = .unknown(type: type)
        }
    }
}

enum ToDoListLiveClientMessage: Encodable, Equatable {
    case subscribe(ToDoListViewerIdentity)
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
