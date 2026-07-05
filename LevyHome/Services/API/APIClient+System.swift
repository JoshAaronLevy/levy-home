extension APIClient {
    func fetchUsers() async throws -> UsersResponse {
        try await send(path: "/api/users")
    }

    func fetchHealth() async throws -> HealthResponse {
        try await send(path: "/health")
    }
}
