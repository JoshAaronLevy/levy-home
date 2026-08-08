import Foundation

extension APIClient {
    func fetchShoppingList() async throws -> ShoppingListResponse {
        try await send(path: "/api/shopping-list")
    }

    func lookupShoppingListItem(named name: String) async throws -> ShoppingListItemLookupResponse {
        try await send(
            path: "/api/shopping-list/items/lookup",
            queryItems: [
                URLQueryItem(name: "name", value: name)
            ]
        )
    }

    func createShoppingListItem(_ request: CreateShoppingListItemRequest) async throws -> ShoppingListMutationResponse {
        try await send(
            path: "/api/shopping-list/items",
            method: .post,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func updateShoppingListItem(
        id itemId: Int,
        _ request: UpdateShoppingListItemRequest
    ) async throws -> ShoppingListMutationResponse {
        try await send(
            path: "/api/shopping-list/items/\(itemId)",
            method: .patch,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func deleteShoppingListItem(
        id itemId: Int,
        actor: String? = nil,
        mutationId: String = UUID().uuidString
    ) async throws -> DeleteShoppingListItemResponse {
        let request = DeleteShoppingListItemRequest(actor: actor, mutationId: mutationId)

        return try await send(
            path: "/api/shopping-list/items/\(itemId)",
            method: .delete,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func fetchToDoList(visibleTo userId: Int? = nil) async throws -> ToDoListResponse {
        try await send(
            path: "/api/todo-list",
            queryItems: userId.map { [URLQueryItem(name: "visibleTo", value: String($0))] } ?? []
        )
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
