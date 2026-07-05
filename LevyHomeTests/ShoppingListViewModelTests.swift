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

    func testLiveConnectionStateBuildsStatusBadges() {
        let viewModel = ShoppingListViewModel(
            liveService: EmptyShoppingListLiveService(),
            loadShoppingList: {
                Self.response(items: [])
            }
        )

        viewModel.applyLiveConnectionState(.connected)
        XCTAssertEqual(
            viewModel.liveStatusBadge,
            ShoppingLiveStatusBadge(
                label: "Live",
                systemImage: "dot.radiowaves.left.and.right",
                tone: .success
            )
        )

        viewModel.applyLiveConnectionState(.reconnecting(delay: 2))
        XCTAssertEqual(
            viewModel.liveStatusBadge,
            ShoppingLiveStatusBadge(
                label: "Reconnecting",
                systemImage: "arrow.clockwise",
                tone: .warning
            )
        )

        viewModel.applyLiveConnectionState(.disconnected)
        XCTAssertEqual(
            viewModel.liveStatusBadge,
            ShoppingLiveStatusBadge(
                label: "Live off",
                systemImage: "wifi.slash",
                tone: .neutral
            )
        )
    }

    func testLiveItemMessagesInsertUpdateAndDeleteItems() async {
        let viewModel = ShoppingListViewModel(loadShoppingList: {
            Self.response(items: [Self.item(id: 15, name: "Cereal", version: 2)])
        })
        await viewModel.loadIfNeeded()

        await viewModel.applyLiveMessage(
            .itemUpdated(
                item: Self.item(id: 15, name: "Older cereal", version: 1),
                mutationId: "older",
                serverTime: "2026-07-05T18:00:00Z"
            )
        )
        XCTAssertEqual(viewModel.items.first?.name, "Cereal")

        await viewModel.applyLiveMessage(
            .itemUpdated(
                item: Self.item(id: 15, name: "Granola", version: 3),
                mutationId: "newer",
                serverTime: "2026-07-05T18:01:00Z"
            )
        )
        XCTAssertEqual(viewModel.items.first?.name, "Granola")

        await viewModel.applyLiveMessage(
            .itemCreated(
                item: Self.item(id: 22, name: "Apples", version: 1),
                mutationId: "created",
                serverTime: "2026-07-05T18:02:00Z"
            )
        )
        XCTAssertEqual(viewModel.items.map(\.id), [15, 22])

        await viewModel.applyLiveMessage(
            .itemDeleted(
                itemId: 15,
                mutationId: "deleted",
                serverTime: "2026-07-05T18:03:00Z"
            )
        )
        XCTAssertEqual(viewModel.items.map(\.id), [22])
    }

    func testPresenceChangedDeduplicatesViewersAndExcludesCurrentViewer() async {
        let viewModel = ShoppingListViewModel(
            currentViewerId: "josh",
            loadShoppingList: {
                Self.response(items: [])
            }
        )

        await viewModel.applyLiveMessage(
            .presenceChanged(
                viewers: [
                    Self.viewer(viewerId: "mallory", displayName: "Mallory", lastSeenAt: "2026-07-05T18:00:00Z"),
                    Self.viewer(viewerId: "mallory", displayName: "Mallory", lastSeenAt: "2026-07-05T18:02:00Z"),
                    Self.viewer(viewerId: "josh", displayName: "Josh", lastSeenAt: "2026-07-05T18:01:00Z")
                ],
                serverTime: "2026-07-05T18:02:00Z"
            )
        )

        XCTAssertEqual(viewModel.activeViewers.map(\.viewerId), ["josh", "mallory"])
        XCTAssertEqual(viewModel.otherActiveViewers.map(\.viewerId), ["mallory"])
        XCTAssertEqual(viewModel.otherActiveViewerLabel, "Mallory viewing")
        XCTAssertEqual(viewModel.activeViewerInitials, ["J", "M"])
    }

    func testSnapshotRequiredRefreshesFromLiveSnapshot() async {
        var responses = [
            Self.response(items: [Self.item(id: 15, name: "Cereal")]),
            Self.response(items: [Self.item(id: 42, name: "Coffee")])
        ]
        let viewModel = ShoppingListViewModel(loadShoppingList: {
            responses.removeFirst()
        })
        await viewModel.loadIfNeeded()

        await viewModel.applyLiveMessage(
            .presenceChanged(
                viewers: [
                    Self.viewer(viewerId: "mallory", displayName: "Mallory", lastSeenAt: "2026-07-05T18:00:00Z")
                ],
                serverTime: "2026-07-05T18:00:00Z"
            )
        )
        await viewModel.applyLiveMessage(
            .snapshotRequired(
                reason: .missedMessages,
                serverTime: "2026-07-05T18:01:00Z"
            )
        )

        XCTAssertEqual(viewModel.items.map(\.id), [42])
        XCTAssertEqual(viewModel.activeViewers, [])
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

    private static func item(id: Int, name: String, version: Int = 1) -> ShoppingListItem {
        ShoppingListItem(
            id: id,
            name: name,
            brand: nil,
            quantity: 1,
            notes: nil,
            purchased: false,
            created: "2026-07-01T17:00:00Z",
            updated: "2026-07-01T17:00:00Z",
            version: version,
            categoryId: nil
        )
    }

    private static func viewer(
        viewerId: String,
        displayName: String,
        lastSeenAt: String
    ) -> ShoppingListViewerPresence {
        ShoppingListViewerPresence(
            viewerId: viewerId,
            displayName: displayName,
            connectionId: "\(viewerId)-connection",
            deviceName: nil,
            lastSeenAt: lastSeenAt
        )
    }
}

private struct EmptyShoppingListLiveService: ShoppingListLiveServicing {
    func messages() -> AsyncStream<ShoppingListLiveMessage> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func connectionStates() -> AsyncStream<ShoppingListLiveConnectionState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func disconnect() {}
}
