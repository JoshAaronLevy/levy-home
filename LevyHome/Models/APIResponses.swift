import Foundation

struct EventsResponse: Codable, Equatable {
    let ok: Bool
    let events: [LevyHomeEvent]
}

struct HomeOverviewResponse: Codable, Equatable {
    let ok: Bool
    let overview: HomeOverview
}

struct QuickActionsResponse: Codable, Equatable {
    let ok: Bool
    let actions: [QuickAction]
    let lightGroups: [LightActionGroup]?
}

struct QuickActionResponse: Codable, Equatable {
    let ok: Bool
    let result: QuickActionResult
}

struct ShoppingListResponse: Codable, Equatable {
    let ok: Bool
    let items: [ShoppingListItem]
    let stores: [ShoppingStore]
    let categories: [ShoppingCategory]
    let generatedAt: String?
}

struct ShoppingListItem: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let brand: String?
    let quantity: Int
    let notes: String?
    let purchased: Bool
    let createdAt: String?
    let updatedAt: String?
    let storeIds: [Int]
    let categoryId: Int?
}

struct ShoppingStore: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let name: String
    let logo: String?
}

struct ShoppingCategory: Codable, Equatable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct NotificationPreferencesResponse: Codable, Equatable {
    let ok: Bool
    let preferences: [NotificationPreference]
    let syncedAt: String?
}

struct RegisteredDevice: Codable, Equatable, Identifiable {
    let id: String?
    let platform: DevicePlatform?
    let provider: PushProvider?
    let environment: APNsEnvironment?
    let registeredAt: String?
    let lastSeenAt: String?
}

struct RegisterDeviceResponse: Codable, Equatable {
    let ok: Bool
    let registeredDeviceCount: Int
    let device: RegisteredDevice?
}

struct TestPushResponse: Codable, Equatable {
    let ok: Bool
    let message: String
    let registeredDeviceCount: Int
    let sentNotificationCount: Int?
    let sentTicketCount: Int?
    let invalidTokenCount: Int?
    let provider: PushProvider?
}

struct HealthResponse: Codable, Equatable {
    let ok: Bool
    let service: String?
    let registeredDeviceCount: Int?
    let recentEventCount: Int?
    let uptimeSeconds: Double?
}
