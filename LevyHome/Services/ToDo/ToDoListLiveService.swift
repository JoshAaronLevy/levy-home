import Foundation

final class ToDoListLiveService: ToDoListLiveServicing {
    static let defaultPresencePingInterval: TimeInterval = 25
    static let defaultReconnectBaseDelay: TimeInterval = 1
    static let defaultReconnectMaximumDelay: TimeInterval = 30

    private let baseURL: URL
    private let viewerIdentity: ToDoListViewerIdentity
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let appLogStore: AppLogStore?
    private let presencePingInterval: TimeInterval

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var presencePingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var continuation: AsyncStream<ToDoListLiveMessage>.Continuation?
    private var isStreaming = false
    private var reconnectAttempt = 0

    init(
        baseURL: URL,
        viewerIdentity: ToDoListViewerIdentity,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        appLogStore: AppLogStore? = nil,
        presencePingInterval: TimeInterval = ToDoListLiveService.defaultPresencePingInterval
    ) {
        self.baseURL = baseURL
        self.viewerIdentity = viewerIdentity
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
        self.appLogStore = appLogStore
        self.presencePingInterval = presencePingInterval
    }

    func messages() -> AsyncStream<ToDoListLiveMessage> {
        AsyncStream(bufferingPolicy: .bufferingNewest(50)) { continuation in
            self.startStreaming(to: continuation)
            continuation.onTermination = { [weak self] _ in
                self?.disconnect()
            }
        }
    }

    func disconnect() {
        isStreaming = false
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

        appLogStore?.record(
            level: .info,
            category: "To Do",
            title: "Live presence disconnected",
            detail: viewerIdentity.displayName
        )
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
        let livePath = "api/todo-list/live"
        let combinedPath = [basePath, livePath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        components.path = "/\(combinedPath)"
        components.query = nil
        components.queryItems = nil
        components.fragment = nil

        guard let url = components.url else {
            throw APIError.invalidURL(path: "/api/todo-list/live")
        }

        return url
    }

    static func reconnectDelay(
        forAttempt attempt: Int,
        baseDelay: TimeInterval = ToDoListLiveService.defaultReconnectBaseDelay,
        maximumDelay: TimeInterval = ToDoListLiveService.defaultReconnectMaximumDelay
    ) -> TimeInterval {
        let safeAttempt = max(0, attempt)
        let exponentialDelay = baseDelay * pow(2, Double(safeAttempt))
        return min(exponentialDelay, maximumDelay)
    }

    private func startStreaming(to continuation: AsyncStream<ToDoListLiveMessage>.Continuation) {
        disconnect()
        self.continuation = continuation
        isStreaming = true
        reconnectAttempt = 0
        openSocket()
    }

    private func openSocket() {
        guard isStreaming else {
            return
        }

        let liveURL: URL

        do {
            liveURL = try Self.liveURL(for: baseURL)
        } catch {
            appLogStore?.record(
                level: .error,
                category: "To Do",
                title: "Live presence URL is invalid",
                detail: error.localizedDescription
            )
            scheduleReconnect()
            return
        }

        let socket = session.webSocketTask(with: liveURL)
        webSocketTask = socket

        appLogStore?.record(
            level: .info,
            category: "To Do",
            title: "Connecting live presence",
            detail: Self.displayURL(liveURL)
        )

        socket.resume()
        receiveTask = Task { [weak self] in
            await self?.runSocket(socket)
        }
    }

    private func runSocket(_ socket: URLSessionWebSocketTask) async {
        do {
            try await send(.subscribe(viewerIdentity), on: socket)
            appLogStore?.record(
                level: .success,
                category: "To Do",
                title: "Live presence subscribed",
                detail: viewerIdentity.displayName
            )

            reconnectAttempt = 0
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
        _ message: ToDoListLiveClientMessage,
        on socket: URLSessionWebSocketTask
    ) async throws {
        let data = try encoder.encode(message)
        let text = String(decoding: data, as: UTF8.self)
        try await socket.send(.string(text))
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
                category: "To Do",
                title: "Ignored unknown live message format"
            )
        }
    }

    private func decodeIncoming(_ data: Data) {
        do {
            let message = try decoder.decode(ToDoListLiveMessage.self, from: data)
            logIncoming(message)
            continuation?.yield(message)
        } catch {
            appLogStore?.record(
                level: .warning,
                category: "To Do",
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
            category: "To Do",
            title: "Live presence interrupted",
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

        appLogStore?.record(
            level: .info,
            category: "To Do",
            title: "Reconnecting live presence",
            detail: "Attempt \(reconnectAttempt). Retrying in \(Int(delay)) seconds."
        )

        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            } catch {
                return
            }

            self?.openSocket()
        }
    }

    private func logIncoming(_ message: ToDoListLiveMessage) {
        switch message {
        case .hello(let connectionId, _):
            appLogStore?.record(
                level: .info,
                category: "To Do",
                title: "Live socket acknowledged",
                detail: "connectionId=\(Self.shortIdentifier(connectionId))"
            )
        case .presenceChanged(let viewers, _):
            appLogStore?.record(
                level: .info,
                category: "To Do",
                title: "Live presence updated",
                detail: "\(viewers.count) active viewer\(viewers.count == 1 ? "" : "s")."
            )
        case .snapshotRequired(let reason, _):
            appLogStore?.record(
                level: .info,
                category: "To Do",
                title: "Refreshing live To Do snapshot",
                detail: reason.rawValue
            )
        case .itemCreated(let item, let mutationId, _), .itemUpdated(let item, let mutationId, _):
            appLogStore?.record(
                level: .info,
                category: "To Do",
                title: "Applied live To Do item",
                detail: "itemId=\(item.id) mutationId=\(Self.shortIdentifier(mutationId))"
            )
        case .itemDeleted(let itemId, let mutationId, _):
            appLogStore?.record(
                level: .info,
                category: "To Do",
                title: "Removed live To Do item",
                detail: "itemId=\(itemId) mutationId=\(Self.shortIdentifier(mutationId))"
            )
        case .unknown(let type):
            appLogStore?.record(
                level: .warning,
                category: "To Do",
                title: "Ignored unknown live message",
                detail: type
            )
        }
    }

    private static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
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
