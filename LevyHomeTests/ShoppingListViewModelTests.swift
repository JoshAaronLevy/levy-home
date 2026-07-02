import XCTest
@testable import LevyHome

@MainActor
final class ShoppingListViewModelTests: XCTestCase {
    func testCancelledRefreshKeepsExistingSnapshotWithoutError() async {
        var responses: [Result<ShoppingListResponse, Error>] = [
            .success(Self.response(items: [Self.item(id: 15, name: "Cereal")])),
            .failure(URLError(.cancelled))
        ]

        let viewModel = ShoppingListViewModel(loadShoppingList: {
            try responses.removeFirst().get()
        })

        await viewModel.loadIfNeeded()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.items.map(\.id), [15])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertFalse(viewModel.isEmpty)
    }

    private static func response(items: [ShoppingListItem]) -> ShoppingListResponse {
        ShoppingListResponse(
            ok: true,
            items: items,
            stores: [],
            categories: [],
            generatedAt: "2026-07-01T17:30:00Z"
        )
    }

    private static func item(id: Int, name: String) -> ShoppingListItem {
        ShoppingListItem(
            id: id,
            name: name,
            brand: nil,
            quantity: 1,
            notes: nil,
            purchased: false,
            created: "2026-07-01T17:00:00Z",
            updated: "2026-07-01T17:00:00Z",
            version: 1,
            categoryId: nil
        )
    }
}
