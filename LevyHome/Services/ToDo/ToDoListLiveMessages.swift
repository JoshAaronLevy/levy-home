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

enum ToDoListLiveMessage: Decodable, Equatable {
    case hello(connectionId: String, serverTime: String)
    case presenceChanged(viewers: [ToDoListViewerPresence], serverTime: String)
    case unknown(type: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case connectionId
        case serverTime
        case viewers
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
