import XCTest
@testable import LevyHome

final class SiriListCommandServiceTests: XCTestCase {
    func testCreatesNewShoppingItemInMiscellaneousWithActorAndMutationID() async {
        let api = ShoppingAPIStub(
            snapshot: makeSnapshot(),
            lookupResults: [nil],
            createdItem: makeItem(id: 101, name: "Paper plates")
        )
        let service = makeService(api: api, mutationIDs: ["create-1"])

        let result = await service.execute(command(title: "  Paper   plates  "))

        XCTAssertEqual(result, .added(SiriListCommandItem(item: makeItem(id: 101, name: "Paper plates"))))
        XCTAssertEqual(api.createdRequests.count, 1)
        XCTAssertEqual(api.createdRequests[0].name, "Paper plates")
        XCTAssertEqual(api.createdRequests[0].quantity, 1)
        XCTAssertEqual(api.createdRequests[0].purchased, false)
        XCTAssertEqual(api.createdRequests[0].categoryId, 42)
        XCTAssertEqual(api.createdRequests[0].actor, "Josh")
        XCTAssertEqual(api.createdRequests[0].mutationId, "create-1")
    }

    func testRejectsWhitespaceOnlyTitleBeforeAnyRequest() async {
        let api = ShoppingAPIStub(snapshot: makeSnapshot())
        let service = makeService(api: api)

        let result = await service.execute(command(title: " \n "))

        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(api.fetchCount, 0)
        XCTAssertEqual(api.lookupCount, 0)
        XCTAssertTrue(api.createdRequests.isEmpty)
    }

    func testTreatsCaseInsensitiveSnapshotDuplicateAsAlreadyPresent() async {
        let existing = makeItem(id: 17, name: "Paper Plates")
        let api = ShoppingAPIStub(
            snapshot: makeSnapshot(items: [existing]),
            lookupResults: [nil]
        )
        let service = makeService(api: api)

        let result = await service.execute(command(title: "paper   plates"))

        XCTAssertEqual(result, .alreadyPresent(SiriListCommandItem(item: existing)))
        XCTAssertEqual(api.lookupCount, 1)
        XCTAssertTrue(api.createdRequests.isEmpty)
        XCTAssertTrue(api.updatedRequests.isEmpty)
    }

    func testRestoresPurchasedShoppingItemWithExistingAddBackSemantics() async {
        let purchased = makeItem(
            id: 18,
            name: "Coffee",
            purchased: true,
            quantity: 2,
            categoryID: 42,
            notes: "Dark roast"
        )
        let restored = makeItem(id: 18, name: "Coffee", purchased: false, quantity: 2, categoryID: 42, notes: "Dark roast")
        let api = ShoppingAPIStub(
            snapshot: makeSnapshot(items: [purchased]),
            lookupResults: [purchased],
            updatedItem: restored
        )
        let service = makeService(api: api, mutationIDs: ["restore-1"])

        let result = await service.execute(command(title: "Coffee"))

        XCTAssertEqual(result, .restored(SiriListCommandItem(item: restored)))
        XCTAssertEqual(api.updatedRequests.count, 1)
        XCTAssertEqual(api.updatedRequests[0].itemID, 18)
        XCTAssertEqual(api.updatedRequests[0].request.purchased, false)
        XCTAssertEqual(api.updatedRequests[0].request.quantity, 2)
        XCTAssertEqual(api.updatedRequests[0].request.actor, "Josh")
        XCTAssertEqual(api.updatedRequests[0].request.mutationId, "restore-1")
    }

    func testFailsWhenMiscellaneousCategoryIsMissingWithoutMutation() async {
        let api = ShoppingAPIStub(
            snapshot: ShoppingListResponse(
                ok: true,
                items: [],
                stores: [],
                categories: [],
                generatedAt: nil
            )
        )
        let service = makeService(api: api)

        let result = await service.execute(command(title: "Dish soap"))

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(api.lookupCount, 0)
        XCTAssertTrue(api.createdRequests.isEmpty)
    }

    func testReconcilesDuplicateConflictWithOneFollowUpLookup() async {
        let existing = makeItem(id: 25, name: "Tea")
        let api = ShoppingAPIStub(
            snapshot: makeSnapshot(),
            lookupResults: [nil, existing],
            createError: APIError.server(statusCode: 409, message: "Duplicate")
        )
        let service = makeService(api: api, mutationIDs: ["create-1"])

        let result = await service.execute(command(title: "Tea"))

        XCTAssertEqual(result, .alreadyPresent(SiriListCommandItem(item: existing)))
        XCTAssertEqual(api.lookupCount, 2)
        XCTAssertEqual(api.createdRequests.count, 1)
    }

    func testUsesFreshMutationIDsForSeparateMutations() async {
        let purchased = makeItem(id: 28, name: "Bread", purchased: true)
        let restored = makeItem(id: 28, name: "Bread", purchased: false)
        let api = ShoppingAPIStub(
            snapshot: makeSnapshot(items: [purchased]),
            lookupResults: [purchased, purchased],
            updatedItem: restored
        )
        let service = makeService(api: api, mutationIDs: ["restore-1", "restore-2"])

        _ = await service.execute(command(title: "Bread"))
        _ = await service.execute(command(title: "Bread"))

        XCTAssertEqual(api.updatedRequests.map(\.request.mutationId), ["restore-1", "restore-2"])
    }

    func testDoesNotRetryCreateAfterCancellation() async {
        let api = ShoppingAPIStub(
            snapshot: makeSnapshot(),
            lookupResults: [nil],
            createError: CancellationError()
        )
        let service = makeService(api: api, mutationIDs: ["create-1"])

        let result = await service.execute(command(title: "Soap"))

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(api.createdRequests.count, 1)
        XCTAssertEqual(api.lookupCount, 1)
    }

    func testDoesNotRetryCreateAfterAmbiguousTransportFailure() async {
        let api = ShoppingAPIStub(
            snapshot: makeSnapshot(),
            lookupResults: [nil],
            createError: APIError.transport("The request timed out.")
        )
        let service = makeService(api: api, mutationIDs: ["create-1"])

        let result = await service.execute(command(title: "Soap"))

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(api.createdRequests.count, 1)
        XCTAssertEqual(api.lookupCount, 1)
    }

    func testRejectsSeveralTitlesBeforeMutation() {
        let resolution = SiriIntentResolver.resolveCommand(
            list: .shopping,
            titles: ["Milk", "Eggs"],
            residentName: "Josh"
        )

        XCTAssertEqual(resolution, .rejected)
    }

    private func makeService(
        api: ShoppingAPIStub,
        mutationIDs: [String] = []
    ) -> SiriListCommandService {
        var mutationIDs = mutationIDs
        return SiriListCommandService(
            shoppingAPI: api,
            makeMutationID: {
                guard !mutationIDs.isEmpty else {
                    return UUID().uuidString
                }

                return mutationIDs.removeFirst()
            }
        )
    }

    private func command(title: String) -> SiriListCommand {
        SiriListCommand(list: .shopping, title: title, residentName: "Josh")
    }

    private func makeSnapshot(items: [ShoppingListItem] = []) -> ShoppingListResponse {
        ShoppingListResponse(
            ok: true,
            items: items,
            stores: [],
            categories: [ShoppingCategory(id: 42, name: "Miscellaneous")],
            generatedAt: nil
        )
    }

    private func makeItem(
        id: Int,
        name: String,
        purchased: Bool = false,
        quantity: Int = 1,
        categoryID: Int? = 42,
        notes: String? = nil
    ) -> ShoppingListItem {
        ShoppingListItem(
            id: id,
            name: name,
            brand: nil,
            quantity: quantity,
            notes: notes,
            purchased: purchased,
            created: nil,
            updated: nil,
            categoryId: categoryID
        )
    }
}

private final class ShoppingAPIStub: SiriShoppingListAPI {
    struct UpdateCall {
        let itemID: Int
        let request: UpdateShoppingListItemRequest
    }

    let snapshot: ShoppingListResponse
    var lookupResults: [ShoppingListItem?]
    let createdItem: ShoppingListItem?
    let updatedItem: ShoppingListItem?
    let createError: Error?

    private(set) var fetchCount = 0
    private(set) var lookupCount = 0
    private(set) var createdRequests: [CreateShoppingListItemRequest] = []
    private(set) var updatedRequests: [UpdateCall] = []

    init(
        snapshot: ShoppingListResponse,
        lookupResults: [ShoppingListItem?] = [],
        createdItem: ShoppingListItem? = nil,
        updatedItem: ShoppingListItem? = nil,
        createError: Error? = nil
    ) {
        self.snapshot = snapshot
        self.lookupResults = lookupResults
        self.createdItem = createdItem
        self.updatedItem = updatedItem
        self.createError = createError
    }

    func fetchShoppingList() async throws -> ShoppingListResponse {
        fetchCount += 1
        return snapshot
    }

    func lookupShoppingListItem(named name: String) async throws -> ShoppingListItemLookupResponse {
        lookupCount += 1
        let match = lookupResults.isEmpty ? nil : lookupResults.removeFirst()
        return ShoppingListItemLookupResponse(ok: true, query: name, match: match)
    }

    func createShoppingListItem(_ request: CreateShoppingListItemRequest) async throws -> ShoppingListMutationResponse {
        createdRequests.append(request)

        if let createError {
            throw createError
        }

        return ShoppingListMutationResponse(
            ok: true,
            item: createdItem ?? ShoppingListItem(
                id: 1,
                name: request.name,
                brand: nil,
                quantity: request.quantity ?? 1,
                notes: nil,
                purchased: request.purchased ?? false,
                created: nil,
                updated: nil,
                categoryId: request.categoryId
            ),
            mutationId: request.mutationId,
            generatedAt: nil
        )
    }

    func updateShoppingListItem(
        id itemId: Int,
        _ request: UpdateShoppingListItemRequest
    ) async throws -> ShoppingListMutationResponse {
        updatedRequests.append(UpdateCall(itemID: itemId, request: request))
        let item = updatedItem ?? snapshot.items.first(where: { $0.id == itemId })!

        return ShoppingListMutationResponse(
            ok: true,
            item: item,
            mutationId: request.mutationId,
            generatedAt: nil
        )
    }
}
