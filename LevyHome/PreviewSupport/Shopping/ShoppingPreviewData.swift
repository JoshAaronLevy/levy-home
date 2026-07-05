enum ShoppingPreviewData {
    static let loadedResponse = ShoppingListResponse(
        ok: true,
        items: [
            ShoppingListItem(
                id: 1,
                name: "Whole milk",
                brand: "Horizon",
                quantity: 2,
                notes: "Half gallon",
                purchased: false,
                created: "2026-06-22T12:00:00.000Z",
                updated: "2026-06-22T12:30:00.000Z",
                categoryId: 2,
                storeListings: [
                    ShoppingItemStoreListing(
                        storeId: 1,
                        storeName: "Target",
                        source: "manual",
                        availability: ShoppingStoreListingAvailability(status: "unknown", checkedAt: nil)
                    )
                ]
            )
        ],
        stores: [
            ShoppingStore(id: 1, name: "Target", logo: "target")
        ],
        categories: [
            ShoppingCategory(id: 2, name: "Dairy")
        ],
        generatedAt: "2026-06-22T12:31:00.000Z"
    )

    static let emptyResponse = ShoppingListResponse(
        ok: true,
        items: [],
        stores: [],
        categories: [],
        generatedAt: "2026-06-22T12:31:00.000Z"
    )
}
