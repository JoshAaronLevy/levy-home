struct PushDeliveryStatus: Codable, Equatable {
    let attempted: Bool
    let skipped: Bool
    let reason: String?
    let ticketCount: Int?
    let sentNotificationCount: Int?
    let failedNotificationCount: Int?
    let invalidTokenCount: Int?
}
