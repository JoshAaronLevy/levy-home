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

    func fetchKrogerProductDiagnostic(named name: String = "Soy Milk") async throws -> KrogerProductDiagnosticResponse {
        try await send(
            path: "/api/debug/kroger/products",
            queryItems: [
                URLQueryItem(name: "term", value: name)
            ]
        )
    }

    func searchKrogerProducts(named name: String) async throws -> KrogerProductSearchResponse {
        try await send(
            path: "/api/shopping-list/products/search",
            queryItems: [
                URLQueryItem(name: "term", value: name)
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

    func deleteShoppingListItem(id itemId: Int, actor: String? = nil) async throws -> DeleteShoppingListItemResponse {
        let request = DeleteShoppingListItemRequest(actor: actor)

        return try await send(
            path: "/api/shopping-list/items/\(itemId)",
            method: .delete,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }
}
