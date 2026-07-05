import Foundation

enum ShoppingListLiveConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(delay: TimeInterval)
    case paused
    case disconnected
}
