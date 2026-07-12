extension APIClient {
    func fetchHealth() async throws -> HealthResponse {
        try await send(path: "/health")
    }
}
