import Foundation

extension APIClient {
    func fetchUsers() async throws -> UsersResponse {
        try await send(path: "/api/users")
    }
}
