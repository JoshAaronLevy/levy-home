import Foundation

extension APIClient {
    func fetchToDoLocations() async throws -> ToDoLocationsResponse {
        try await send(path: "/api/todo/locations")
    }

    func createToDoLocation(_ request: CreateToDoLocationRequest) async throws -> ToDoLocationMutationResponse {
        try await send(path: "/api/todo/locations", method: .post, body: request)
    }

}
