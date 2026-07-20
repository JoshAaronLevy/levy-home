import Foundation

enum AppNavigationDestination {
    static let pendingDestinationKey = "appNavigation.pendingDestination"

    static func savePendingDestination(_ destination: String) {
        UserDefaults.standard.set(destination, forKey: pendingDestinationKey)
    }

    static func consumePendingDestination() -> String? {
        defer { UserDefaults.standard.removeObject(forKey: pendingDestinationKey) }
        return UserDefaults.standard.string(forKey: pendingDestinationKey)
    }
}

extension Notification.Name {
    static let levyHomeOpenShopping = Notification.Name("levyHomeOpenShopping")
    static let levyHomeOpenToDo = Notification.Name("levyHomeOpenToDo")
}
