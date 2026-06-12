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
    let invalidTokenCount: Int?
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
