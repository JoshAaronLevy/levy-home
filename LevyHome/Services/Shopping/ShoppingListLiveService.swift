import Foundation

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
