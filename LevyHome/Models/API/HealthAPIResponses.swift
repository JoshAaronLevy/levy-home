struct HealthResponse: Codable, Equatable {
    let ok: Bool
    let service: String?
    let registeredDeviceCount: Int?
    let recentEventCount: Int?
    let uptimeSeconds: Double?
}
