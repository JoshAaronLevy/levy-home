struct ShoppingListViewerIdentity: Equatable {
    let viewerId: String
    let displayName: String
    let deviceName: String?

    init(viewerId: String, displayName: String, deviceName: String? = nil) {
        self.viewerId = viewerId
        self.displayName = displayName
        self.deviceName = deviceName.flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct ShoppingListViewerPresence: Codable, Equatable, Identifiable {
    let viewerId: String
    let displayName: String
    let connectionId: String
    let deviceName: String?
    let lastSeenAt: String

    var id: String {
        viewerId
    }
}
