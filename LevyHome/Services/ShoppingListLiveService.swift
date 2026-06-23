import Foundation

protocol ShoppingListLiveServicing {
    func messages() -> AsyncStream<ShoppingListLiveMessage>
    func connectionStates() -> AsyncStream<ShoppingListLiveConnectionState>
    func disconnect()
}

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

enum ShoppingListLiveConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(delay: TimeInterval)
    case paused
    case disconnected
}

final class ShoppingListLiveService: ShoppingListLiveServicing {
    static let defaultPresencePingInterval: TimeInterval = 25
    static let defaultReconnectBaseDelay: TimeInterval = 1
    static let defaultReconnectMaximumDelay: TimeInterval = 30
    static let pausedReconnectAttemptThreshold = 3

    private let baseURL: URL
    private let viewerIdentity: ShoppingListViewerIdentity
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let appLogStore: AppLogStore?
    private let presencePingInterval: TimeInterval

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var presencePingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var continuation: AsyncStream<ShoppingListLiveMessage>.Continuation?
    private var stateContinuation: AsyncStream<ShoppingListLiveConnectionState>.Continuation?
    private var isStreaming = false
    private var reconnectAttempt = 0
    private(set) var connectionState: ShoppingListLiveConnectionState = .idle

    init(
        baseURL: URL,
        viewerIdentity: ShoppingListViewerIdentity,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        appLogStore: AppLogStore? = nil,
        presencePingInterval: TimeInterval = ShoppingListLiveService.defaultPresencePingInterval
    ) {
        self.baseURL = baseURL
        self.viewerIdentity = viewerIdentity
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
        self.appLogStore = appLogStore
        self.presencePingInterval = presencePingInterval
    }

    func messages() -> AsyncStream<ShoppingListLiveMessage> {
        AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            self.startStreaming(to: continuation)
            continuation.onTermination = { [weak self] _ in
                self?.disconnect()
            }
        }
    }

    func connectionStates() -> AsyncStream<ShoppingListLiveConnectionState> {
        AsyncStream(bufferingPolicy: .bufferingNewest(20)) { continuation in
            self.stateContinuation = continuation
            continuation.yield(self.connectionState)
            continuation.onTermination = { [weak self] _ in
                self?.stateContinuation = nil
            }
        }
    }

    func disconnect() {
        isStreaming = false
        let wasActive = connectionState != .idle && connectionState != .disconnected
        setConnectionState(.disconnected)
        reconnectTask?.cancel()
        receiveTask?.cancel()
        presencePingTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        reconnectTask = nil
        receiveTask = nil
        presencePingTask = nil
        webSocketTask = nil
        reconnectAttempt = 0

        let activeContinuation = continuation
        continuation = nil
        activeContinuation?.finish()

        if wasActive {
            appLogStore?.record(
                level: .info,
                category: "Shopping List",
                title: "Live updates disconnected",
                detail: viewerIdentity.displayName
            )
        }
    }

    static func liveURL(for apiBaseURL: URL) throws -> URL {
        guard
            var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            components.host != nil
        else {
            throw APIError.invalidBaseURL(apiBaseURL.absoluteString)
        }

        switch scheme {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            throw APIError.invalidBaseURL(apiBaseURL.absoluteString)
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let livePath = "api/shopping-list/live"
        let combinedPath = [basePath, livePath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        components.path = "/\(combinedPath)"
        components.query = nil
        components.queryItems = nil
        components.fragment = nil

        guard let url = components.url else {
            throw APIError.invalidURL(path: "/api/shopping-list/live")
        }

        return url
    }

    static func reconnectDelay(
        forAttempt attempt: Int,
        baseDelay: TimeInterval = ShoppingListLiveService.defaultReconnectBaseDelay,
        maximumDelay: TimeInterval = ShoppingListLiveService.defaultReconnectMaximumDelay
    ) -> TimeInterval {
        let safeAttempt = max(0, attempt)
        let exponentialDelay = baseDelay * pow(2, Double(safeAttempt))
        return min(exponentialDelay, maximumDelay)
    }

    private func startStreaming(to continuation: AsyncStream<ShoppingListLiveMessage>.Continuation) {
        disconnect()
        self.continuation = continuation
        isStreaming = true
        setConnectionState(.connecting)
        reconnectAttempt = 0
        openSocket(requiresSnapshotBeforeReceive: false)
    }

    private func openSocket(requiresSnapshotBeforeReceive: Bool) {
        guard isStreaming else {
            return
        }

        let liveURL: URL

        do {
            liveURL = try Self.liveURL(for: baseURL)
        } catch {
            appLogStore?.record(
                level: .error,
                category: "Shopping List",
                title: "Live updates URL is invalid",
                detail: error.localizedDescription
            )
            scheduleReconnect()
            return
        }

        let socket = session.webSocketTask(with: liveURL)
        webSocketTask = socket
        setConnectionState(reconnectAttempt == 0 ? .connecting : .reconnecting(delay: 0))

        appLogStore?.record(
            level: .info,
            category: "Shopping List",
            title: "Connecting live updates",
            detail: Self.displayURL(liveURL)
        )

        socket.resume()
        receiveTask = Task { [weak self] in
            await self?.runSocket(socket, requiresSnapshotBeforeReceive: requiresSnapshotBeforeReceive)
        }
    }

    private func runSocket(
        _ socket: URLSessionWebSocketTask,
        requiresSnapshotBeforeReceive: Bool
    ) async {
        do {
            try await send(.subscribe(viewerIdentity), on: socket)
            appLogStore?.record(
                level: .info,
                category: "Shopping List",
                title: "Live presence subscribed",
                detail: viewerIdentity.displayName
            )
            markConnected(socket)

            if requiresSnapshotBeforeReceive {
                continuation?.yield(
                    .snapshotRequired(
                        reason: .missedMessages,
                        serverTime: Self.currentServerTime()
                    )
                )
            }

            startPresencePing(on: socket)

            while isStreaming, webSocketTask === socket {
                let message = try await socket.receive()
                handleIncoming(message)
            }
        } catch {
            handleSocketFailure(error, socket: socket)
        }
    }

    private func startPresencePing(on socket: URLSessionWebSocketTask) {
        presencePingTask?.cancel()
        presencePingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(for: presencePingInterval))
                    try await send(.presencePing(viewerId: viewerIdentity.viewerId), on: socket)
                } catch {
                    if !Task.isCancelled {
                        handleSocketFailure(error, socket: socket)
                    }
                    return
                }
            }
        }
    }

    private func send(
        _ message: ShoppingListLiveClientMessage,
        on socket: URLSessionWebSocketTask
    ) async throws {
        let data = try encoder.encode(message)
        let text = String(decoding: data, as: UTF8.self)
        try await socket.send(.string(text))
    }

    private func markConnected(_ socket: URLSessionWebSocketTask) {
        guard isStreaming, webSocketTask === socket else {
            return
        }

        reconnectAttempt = 0
        setConnectionState(.connected)
        appLogStore?.record(
            level: .success,
            category: "Shopping List",
            title: "Live updates connected",
            detail: viewerIdentity.displayName
        )
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            decodeIncoming(Data(text.utf8))
        case .data(let data):
            decodeIncoming(data)
        @unknown default:
            appLogStore?.record(
                level: .warning,
                category: "Shopping List",
                title: "Ignored unknown live message format"
            )
        }
    }

    private func decodeIncoming(_ data: Data) {
        do {
            let message = try decoder.decode(ShoppingListLiveMessage.self, from: data)
            logIncoming(message)
            continuation?.yield(message)
        } catch {
            appLogStore?.record(
                level: .warning,
                category: "Shopping List",
                title: "Ignored malformed live message",
                detail: error.localizedDescription
            )
        }
    }

    private func handleSocketFailure(_ error: Error, socket: URLSessionWebSocketTask) {
        guard isStreaming, webSocketTask === socket else {
            return
        }

        webSocketTask = nil
        receiveTask = nil
        presencePingTask?.cancel()
        presencePingTask = nil
        socket.cancel(with: .goingAway, reason: nil)

        appLogStore?.record(
            level: .warning,
            category: "Shopping List",
            title: "Live updates interrupted",
            detail: error.localizedDescription
        )

        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isStreaming else {
            return
        }

        reconnectTask?.cancel()

        let delay = Self.reconnectDelay(forAttempt: reconnectAttempt)
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let isPausedState = attempt >= Self.pausedReconnectAttemptThreshold
        setConnectionState(isPausedState ? .paused : .reconnecting(delay: delay))

        appLogStore?.record(
            level: isPausedState ? .warning : .info,
            category: "Shopping List",
            title: isPausedState ? "Live updates paused" : "Reconnecting live updates",
            detail: "Attempt \(attempt). Retrying in \(Int(delay)) seconds."
        )

        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            } catch {
                return
            }

            self?.openSocket(requiresSnapshotBeforeReceive: true)
        }
    }

    private func setConnectionState(_ state: ShoppingListLiveConnectionState) {
        guard connectionState != state else {
            return
        }

        connectionState = state
        stateContinuation?.yield(state)
    }

    private func logIncoming(_ message: ShoppingListLiveMessage) {
        switch message {
        case .hello(let connectionId, _):
            appLogStore?.record(
                level: .info,
                category: "Shopping List",
                title: "Live socket acknowledged",
                detail: "connectionId=\(Self.shortIdentifier(connectionId))"
            )
        case .presenceChanged(let viewers, _):
            appLogStore?.record(
                level: .info,
                category: "Shopping List",
                title: "Live presence updated",
                detail: "\(viewers.count) active viewer\(viewers.count == 1 ? "" : "s")."
            )
        case .snapshotRequired(let reason, _):
            appLogStore?.record(
                level: .info,
                category: "Shopping List",
                title: "Refreshing live snapshot",
                detail: reason.rawValue
            )
        case .itemCreated(let item, let mutationId, _):
            appLogStore?.record(
                level: .success,
                category: "Shopping List",
                title: "Live item created",
                detail: "itemId=\(item.id) mutationId=\(Self.shortIdentifier(mutationId))"
            )
        case .itemUpdated(let item, let mutationId, _):
            appLogStore?.record(
                level: .success,
                category: "Shopping List",
                title: "Live item updated",
                detail: "itemId=\(item.id) mutationId=\(Self.shortIdentifier(mutationId))"
            )
        case .itemDeleted(let itemId, let mutationId, _):
            appLogStore?.record(
                level: .success,
                category: "Shopping List",
                title: "Live item deleted",
                detail: "itemId=\(itemId) mutationId=\(Self.shortIdentifier(mutationId))"
            )
        case .storesChanged(let stores, let mutationId, _):
            appLogStore?.record(
                level: .info,
                category: "Shopping List",
                title: "Live stores updated",
                detail: "count=\(stores.count) mutationId=\(Self.shortIdentifier(mutationId))"
            )
        case .categoriesChanged(let categories, let mutationId, _):
            appLogStore?.record(
                level: .info,
                category: "Shopping List",
                title: "Live categories updated",
                detail: "count=\(categories.count) mutationId=\(Self.shortIdentifier(mutationId))"
            )
        case .unknown(let type):
            appLogStore?.record(
                level: .warning,
                category: "Shopping List",
                title: "Ignored unknown live message",
                detail: type
            )
        }
    }

    private static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    private static func currentServerTime() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func displayURL(_ url: URL) -> String {
        if let host = url.host {
            return "\(url.scheme ?? "ws")://\(host)\(url.path)"
        }

        return url.path
    }

    private static func shortIdentifier(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmedValue.prefix(12))
    }
}
