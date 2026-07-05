import Foundation

extension APIClient {
    func fetchToDoLocations() async throws -> ToDoLocationsResponse {
        try await send(path: "/api/todo/locations")
    }

    func createToDoLocation(_ request: CreateToDoLocationRequest) async throws -> ToDoLocationMutationResponse {
        try await send(path: "/api/todo/locations", method: .post, body: request)
    }

    func fetchToDoList() async throws -> ToDoListResponse {
        try await send(path: "/api/todo-list")
    }

    func createToDoItem(_ request: CreateToDoItemRequest) async throws -> ToDoListMutationResponse {
        try await send(
            path: "/api/todo-list/items",
            method: .post,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func updateToDoItem(
        id itemId: Int,
        _ request: UpdateToDoItemRequest
    ) async throws -> ToDoListMutationResponse {
        try await send(
            path: "/api/todo-list/items/\(itemId)",
            method: .patch,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func deleteToDoItem(id itemId: Int, actor: String? = nil) async throws -> DeleteToDoItemResponse {
        let request = DeleteToDoItemRequest(actor: actor)

        return try await send(
            path: "/api/todo-list/items/\(itemId)",
            method: .delete,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }
}
