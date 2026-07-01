import Foundation

struct EventDisplayMetadata: Codable, Equatable {
    let title: String
    let body: String
    let severity: DisplaySeverity
}

struct EventPushStatus: Codable, Equatable {
    let attempted: Bool
    let skipped: Bool
    let reason: String?
    let ticketCount: Int?
    let sentNotificationCount: Int?
    let failedNotificationCount: Int?
    let invalidTokenCount: Int?

    init(
        attempted: Bool,
        skipped: Bool,
        reason: String? = nil,
        ticketCount: Int? = nil,
        sentNotificationCount: Int? = nil,
        failedNotificationCount: Int? = nil,
        invalidTokenCount: Int? = nil
    ) {
        self.attempted = attempted
        self.skipped = skipped
        self.reason = reason
        self.ticketCount = ticketCount
        self.sentNotificationCount = sentNotificationCount
        self.failedNotificationCount = failedNotificationCount
        self.invalidTokenCount = invalidTokenCount
    }
}

struct LevyHomeEvent: Codable, Equatable, Identifiable {
    let id: String
    let type: EventType
    let entityId: String
    let category: HomeAssistantCategory?
    let severity: HomeAssistantPayloadSeverity?
    let source: String?
    let occurredAt: String
    let title: String?
    let message: String?
    let receivedAt: String
    let display: EventDisplayMetadata
    let push: EventPushStatus?
}
