import Foundation

protocol ShoppingLiveActivityRegistrationServicing {
    func registerShoppingLiveActivity(
        _ request: ShoppingLiveActivityRegistrationRequest
    ) async throws -> ShoppingLiveActivityRegistrationResponse
}

extension APIClient: ShoppingLiveActivityRegistrationServicing {}

extension APIClient {
    func fetchShoppingList() async throws -> ShoppingListResponse {
        try await send(path: "/api/shopping-list")
    }

    func sendShoppingLiveActivityDebugDelivery(
        event: ShoppingLiveActivityDebugEvent,
        excludeResident: String?
    ) async throws -> ShoppingLiveActivityDebugDeliveryResponse {
        let body = excludeResident.map { ["excludeResident": $0] } ?? [:]
        return try await send(
            path: "/api/debug/shopping-live-activity/\(event.rawValue)",
            method: .post,
            body: body
        )
    }

    func fetchActiveShoppingTrip() async throws -> ShoppingActiveTripResponse {
        try await send(path: "/api/shopping-list/trip")
    }

    func startShoppingTrip(_ request: StartShoppingTripRequest) async throws -> ShoppingTripMutationResponse {
        try await send(
            path: "/api/shopping-list/trip/start",
            method: .post,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func endShoppingTrip(_ request: EndShoppingTripRequest) async throws -> ShoppingTripMutationResponse {
        try await send(
            path: "/api/shopping-list/trip/end",
            method: .post,
            body: request,
            additionalHeaders: Self.mutationHeaders(for: request.mutationId)
        )
    }

    func registerShoppingLiveActivity(
        _ request: ShoppingLiveActivityRegistrationRequest
    ) async throws -> ShoppingLiveActivityRegistrationResponse {
        try await send(
            path: "/api/shopping-list/live-activities/registrations",
            method: .post,
            body: request
        )
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
}
