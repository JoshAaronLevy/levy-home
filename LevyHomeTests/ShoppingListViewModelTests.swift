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

    func testEditSurvivesOlderRefreshThatFinishesAfterMutation() async throws {
        let original = Self.item(id: 15, name: "Cereal", version: 1)
        let updated = Self.item(id: 15, name: "Granola", version: 2)
        let refreshGate = ShoppingListResponseGate()
        var loadCount = 0
        var capturedRequest: UpdateShoppingListItemRequest?
        let viewModel = ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: {
                loadCount += 1

                switch loadCount {
                case 1:
                    return Self.response(items: [original])
                case 2:
                    return await refreshGate.waitForResponse()
                default:
                    return Self.response(items: [updated], activeTrip: Self.trip())
                }
            },
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, request in
                capturedRequest = request
                return ShoppingListMutationResponse(
                    ok: true,
                    item: updated,
                    activeTrip: Self.trip(),
                    mutationId: request.mutationId,
                    generatedAt: "2026-07-11T20:01:00Z"
                )
            },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") }
        )
        await viewModel.loadIfNeeded()

        let refreshTask = Task { await viewModel.refresh() }
        await refreshGate.waitUntilStarted()
        var draft = ShoppingItemDraft(item: original)
        draft.name = "Granola"

        try await viewModel.updateItem(original, with: draft)
        await refreshGate.resume(with: Self.response(items: [original]))
        await refreshTask.value

        XCTAssertEqual(viewModel.items.first?.name, "Granola")
        XCTAssertEqual(viewModel.items.first?.version, 2)
        XCTAssertEqual(viewModel.activeTrip?.id, Self.trip().id)
        XCTAssertEqual(capturedRequest?.name, "Granola")
        XCTAssertNil(capturedRequest?.purchased)
        XCTAssertNil(capturedRequest?.quantity)
        XCTAssertNil(capturedRequest?.brand)
        XCTAssertFalse(viewModel.isMutatingItem(original.id))
    }

    func testTransportFailureReconcilesThenRetriesOnlyWhenEditWasNotCommitted() async throws {
        let original = Self.item(id: 15, name: "Cereal", version: 1)
        let updated = Self.item(id: 15, name: "Granola", version: 2)
        var loadCount = 0
        var updateRequests: [UpdateShoppingListItemRequest] = []
        let viewModel = ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: {
                loadCount += 1
                return Self.response(items: [original])
            },
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, request in
                updateRequests.append(request)

                if updateRequests.count == 1 {
                    throw APIError.transport("The network connection was lost.")
                }

                return ShoppingListMutationResponse(
                    ok: true,
                    item: updated,
                    mutationId: request.mutationId,
                    generatedAt: "2026-07-11T20:02:00Z"
                )
            },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") }
        )
        await viewModel.loadIfNeeded()
        var draft = ShoppingItemDraft(item: original)
        draft.name = "Granola"

        try await viewModel.updateItem(original, with: draft)

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(updateRequests.count, 2)
        XCTAssertEqual(updateRequests.map(\.mutationId), [
            updateRequests[0].mutationId,
            updateRequests[0].mutationId
        ])
        XCTAssertEqual(viewModel.items.first?.name, "Granola")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isMutatingItem(original.id))
    }

    func testRetryAppliesTripStateReturnedAfterReconciliationAdvancedIt() async throws {
        let original = Self.item(id: 15, name: "Cereal", version: 1)
        let updated = Self.item(id: 15, name: "Granola", version: 2)
        let initialTrip = Self.trip(version: 1, pickedUpCount: 0, remainingCount: 1)
        let reconciledTrip = Self.trip(version: 2, pickedUpCount: 1, remainingCount: 0)
        let retryTrip = Self.trip(version: 3, pickedUpCount: 0, remainingCount: 1)
        var loadCount = 0
        var updateCallCount = 0
        let viewModel = ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: {
                loadCount += 1
                return Self.response(
                    items: [original],
                    activeTrip: loadCount == 1 ? initialTrip : reconciledTrip
                )
            },
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, request in
                updateCallCount += 1

                if updateCallCount == 1 {
                    throw APIError.transport("The network connection was lost.")
                }

                return ShoppingListMutationResponse(
                    ok: true,
                    item: updated,
                    activeTrip: retryTrip,
                    mutationId: request.mutationId,
                    generatedAt: "2026-07-11T20:02:00Z"
                )
            },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") }
        )
        await viewModel.loadIfNeeded()
        var draft = ShoppingItemDraft(item: original)
        draft.name = "Granola"

        try await viewModel.updateItem(original, with: draft)

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(updateCallCount, 2)
        XCTAssertEqual(viewModel.activeTrip?.version, 3)
        XCTAssertEqual(viewModel.activeTrip?.remainingCount, 1)
    }

    func testTransportFailureAcceptsReconciledEditWithoutDuplicateRetry() async throws {
        let original = Self.item(id: 15, name: "Cereal", version: 1)
        let updated = Self.item(id: 15, name: "Granola", version: 2)
        var loadCount = 0
        var updateCallCount = 0
        let viewModel = ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: {
                loadCount += 1
                return Self.response(items: loadCount == 1 ? [original] : [updated])
            },
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, _ in
                updateCallCount += 1
                throw APIError.transport("The response connection was lost after commit.")
            },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") }
        )
        await viewModel.loadIfNeeded()
        var draft = ShoppingItemDraft(item: original)
        draft.name = "Granola"

        try await viewModel.updateItem(original, with: draft)

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(updateCallCount, 1)
        XCTAssertEqual(viewModel.items.first?.name, "Granola")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testTransportFailureDoesNotRetryWhenReconciliationCannotConfirmState() async {
        let original = Self.item(id: 15, name: "Cereal", version: 1)
        var loadCount = 0
        var updateCallCount = 0
        let viewModel = ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: {
                loadCount += 1

                if loadCount == 1 {
                    return Self.response(items: [original])
                }

                throw APIError.transport("The shopping list could not be reloaded.")
            },
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, _ in
                updateCallCount += 1
                throw APIError.transport("The response connection was lost after commit.")
            },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") }
        )
        await viewModel.loadIfNeeded()
        var draft = ShoppingItemDraft(item: original)
        draft.name = "Granola"

        do {
            try await viewModel.updateItem(original, with: draft)
            XCTFail("Expected the uncertain update to remain failed.")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                APIError.transport("The response connection was lost after commit.")
            )
        }

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(updateCallCount, 1)
        XCTAssertEqual(viewModel.items.first?.name, "Cereal")
    }

    func testReconciledEditSurvivesOlderRefreshThatWasAlreadyInFlight() async throws {
        let original = Self.item(id: 15, name: "Cereal", version: 1)
        let updated = Self.item(id: 15, name: "Granola", version: 2)
        let staleRefreshGate = ShoppingListResponseGate()
        var loadCount = 0
        var updateCallCount = 0
        let viewModel = ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: {
                loadCount += 1

                switch loadCount {
                case 1:
                    return Self.response(items: [original])
                case 2:
                    return await staleRefreshGate.waitForResponse()
                default:
                    return Self.response(items: [updated])
                }
            },
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, _ in
                updateCallCount += 1
                throw APIError.transport("The response connection was lost after commit.")
            },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") }
        )
        await viewModel.loadIfNeeded()

        let staleRefreshTask = Task { await viewModel.refresh() }
        await staleRefreshGate.waitUntilStarted()
        var draft = ShoppingItemDraft(item: original)
        draft.name = "Granola"
        try await viewModel.updateItem(original, with: draft)
        await staleRefreshGate.resume(with: Self.response(items: [original]))
        await staleRefreshTask.value

        XCTAssertEqual(loadCount, 4)
        XCTAssertEqual(updateCallCount, 1)
        XCTAssertEqual(viewModel.items.first?.name, "Granola")
        XCTAssertEqual(viewModel.items.first?.version, 2)
    }

    func testDelayedEditResponseDoesNotResurrectTripEndedByLiveUpdate() async throws {
        let original = Self.item(id: 15, name: "Cereal", version: 1)
        let updated = Self.item(id: 15, name: "Granola", version: 2)
        let trip = Self.trip()
        let updateGate = ShoppingListMutationResponseGate()
        let viewModel = ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: {
                Self.response(items: [original])
            },
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, request in
                await updateGate.waitForResponse(
                    ShoppingListMutationResponse(
                        ok: true,
                        item: updated,
                        activeTrip: trip,
                        mutationId: request.mutationId,
                        generatedAt: "2026-07-11T20:03:00Z"
                    )
                )
            },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") }
        )
        await viewModel.loadIfNeeded()
        var draft = ShoppingItemDraft(item: original)
        draft.name = "Granola"

        let updateTask = Task {
            try await viewModel.updateItem(original, with: draft)
        }
        await updateGate.waitUntilStarted()
        await viewModel.applyLiveMessage(
            .tripEnded(
                trip: trip,
                mutationId: "end-trip",
                serverTime: "2026-07-11T20:02:30Z"
            )
        )
        await updateGate.resume()
        try await updateTask.value

        XCTAssertEqual(viewModel.items.first?.name, "Granola")
        XCTAssertNil(viewModel.activeTrip)
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
        XCTAssertEqual(viewModel.residentAvatarStates.map(\.initial), ["J", "M"])
        XCTAssertEqual(viewModel.residentAvatarStates.map(\.isViewing), [true, true])
    }

    func testResidentAvatarStatesAlwaysShowJoshAndMallory() {
        let viewModel = ShoppingListViewModel(
            currentViewerId: "josh",
            loadShoppingList: {
                Self.response(items: [])
            }
        )

        XCTAssertEqual(viewModel.residentAvatarStates.map(\.initial), ["J", "M"])
        XCTAssertEqual(viewModel.residentAvatarStates.map(\.isViewing), [true, false])
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

    func testLoadIfNeededRetainsTheCurrentSnapshotUntilLiveRequestsResync() async {
        var loadCount = 0
        let viewModel = ShoppingListViewModel(loadShoppingList: {
            loadCount += 1
            return Self.response(items: [Self.item(id: loadCount, name: "Item \(loadCount)")])
        })

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(viewModel.items.map(\.id), [1])

        await viewModel.applyLiveMessage(
            .snapshotRequired(
                reason: .connected,
                serverTime: "2026-08-16T18:00:00Z"
            )
        )

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.items.map(\.id), [2])
    }

    func testStartTripUsesRegisteredOriginDeviceAndPublishesCanonicalActiveTrip() async {
        var receivedRequest: StartShoppingTripRequest?
        let trip = Self.trip()
        let viewModel = Self.tripViewModel(
            items: [Self.item(id: 15, name: "Cereal")],
            start: { request in
                receivedRequest = request
                return ShoppingTripMutationResponse(
                    ok: true,
                    trip: trip,
                    activeTrip: trip,
                    mutationId: request.mutationId,
                    displayDisposition: ShoppingTripDisplayDisposition(
                        tripId: trip.id,
                        pushDeviceId: "device-josh",
                        resident: "Josh",
                        kind: "start_locally",
                        remoteStartCount: 1
                    ),
                    generatedAt: nil
                )
            }
        )
        await viewModel.loadIfNeeded()

        let response = await viewModel.startTrip(originatingPushDeviceId: "device-josh")

        XCTAssertEqual(receivedRequest?.actor, "Josh")
        XCTAssertEqual(receivedRequest?.originatingPushDeviceId, "device-josh")
        XCTAssertEqual(response?.displayDisposition?.kind, "start_locally")
        XCTAssertEqual(viewModel.activeTrip?.id, trip.id)
        XCTAssertFalse(viewModel.isStartingTrip)
    }

    func testStartTripExplainsMissingNeededItemsAndMissingDeviceRegistration() async {
        let emptyViewModel = Self.tripViewModel(items: [])
        await emptyViewModel.loadIfNeeded()
        let emptyResponse = await emptyViewModel.startTrip(originatingPushDeviceId: "device-josh")
        XCTAssertNil(emptyResponse)
        XCTAssertEqual(emptyViewModel.errorMessage, "Add at least one needed item before starting a shopping trip.")

        let missingDeviceViewModel = Self.tripViewModel(items: [Self.item(id: 15, name: "Cereal")])
        await missingDeviceViewModel.loadIfNeeded()
        let missingDeviceResponse = await missingDeviceViewModel.startTrip(originatingPushDeviceId: nil)
        XCTAssertNil(missingDeviceResponse)
        XCTAssertEqual(
            missingDeviceViewModel.errorMessage,
            "This iPhone is still registering for notifications. Try starting the trip again in a moment."
        )
    }

    func testStartTripKeepsListUsableWhenTheAPIFails() async {
        let viewModel = Self.tripViewModel(
            items: [Self.item(id: 15, name: "Cereal")],
            start: { _ in throw APIError.server(statusCode: 503, message: "Trips unavailable.") }
        )
        await viewModel.loadIfNeeded()

        let response = await viewModel.startTrip(originatingPushDeviceId: "device-josh")
        XCTAssertNil(response)
        XCTAssertEqual(viewModel.items.map(\.id), [15])
        XCTAssertEqual(viewModel.errorMessage, "Trips unavailable.")
        XCTAssertFalse(viewModel.isStartingTrip)
    }

    func testActiveTripDisplayClaimIsCachedForTheActiveTripAndDevice() async {
        let trip = Self.trip()
        let disposition = ShoppingTripDisplayDisposition(
            tripId: trip.id,
            pushDeviceId: "device-josh",
            resident: "Josh",
            kind: "start_locally",
            remoteStartCount: 1
        )
        var claimCount = 0
        var activeTripForLoad: ShoppingTrip? = trip
        let viewModel = ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: {
                Self.response(items: [Self.item(id: 15, name: "Cereal")], activeTrip: activeTripForLoad)
            },
            lookupShoppingListItem: { name in
                ShoppingListItemLookupResponse(ok: true, query: name, match: nil)
            },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, _ in throw APIError.transport("Unused") },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") },
            claimShoppingTripDisplay: { tripId, request in
                claimCount += 1
                XCTAssertEqual(tripId, trip.id)
                XCTAssertEqual(request.pushDeviceId, "device-josh")
                return ClaimShoppingTripDisplayResponse(
                    ok: true,
                    displayDisposition: disposition,
                    generatedAt: "2026-08-16T18:00:00Z"
                )
            }
        )
        await viewModel.loadIfNeeded()

        let first = await viewModel.claimActiveTripDisplay(pushDeviceId: "device-josh")
        let second = await viewModel.claimActiveTripDisplay(pushDeviceId: "device-josh")

        activeTripForLoad = nil
        await viewModel.refresh()
        activeTripForLoad = trip
        await viewModel.refresh()
        let restored = await viewModel.claimActiveTripDisplay(pushDeviceId: "device-josh")

        XCTAssertEqual(claimCount, 2)
        XCTAssertEqual(first, disposition)
        XCTAssertEqual(second, disposition)
        XCTAssertEqual(restored, disposition)
    }

    func testStockPriceCheckStartsOnlyOnceDuringRapidTaps() async {
        let startGate = StockPriceCheckStartGate()
        var startCount = 0
        var receivedRequest: StartShoppingStockPriceCheckRequest?
        let queuedJob = Self.stockPriceCheckJob(status: .queued)
        let viewModel = Self.stockPriceCheckViewModel(
            items: [Self.item(id: 15, name: "Cereal")],
            start: { request in
                startCount += 1
                receivedRequest = request
                return .accepted(await startGate.waitForJob())
            }
        )
        await viewModel.loadIfNeeded()

        let firstStart = Task { await viewModel.startStockPriceCheck() }
        await startGate.waitUntilStarted()
        let secondResult = await viewModel.startStockPriceCheck()
        await startGate.resume(with: queuedJob)
        let firstResult = await firstStart.value

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(receivedRequest?.actor, "Josh")
        XCTAssertFalse(receivedRequest?.mutationId.isEmpty ?? true)
        XCTAssertEqual(firstResult?.id, queuedJob.id)
        XCTAssertNil(secondResult)
        XCTAssertEqual(viewModel.stockPriceCheckJob?.id, queuedJob.id)
    }

    func testStockPriceCheckAdoptsTheServerActiveJob() async {
        let activeJob = Self.stockPriceCheckJob(id: "already-running", status: .running, processed: 2, requested: 5)
        let viewModel = Self.stockPriceCheckViewModel(
            items: [Self.item(id: 15, name: "Cereal")],
            start: { _ in .active(activeJob) }
        )
        await viewModel.loadIfNeeded()

        let result = await viewModel.startStockPriceCheck()

        XCTAssertEqual(result?.id, activeJob.id)
        XCTAssertEqual(viewModel.stockPriceCheckJob, activeJob)
        XCTAssertTrue(viewModel.isStockPriceCheckActive)
        XCTAssertEqual(viewModel.stockPriceCheckProgressLabel, "2 of 5")
    }

    func testStockPriceCheckPollsProgressAndRefreshesAtTerminalState() async {
        let initial = Self.item(id: 15, name: "Cereal", version: 1)
        let refreshed = Self.item(id: 15, name: "Cereal", version: 2)
        var listLoadCount = 0
        var jobs = [
            Self.stockPriceCheckJob(status: .running, processed: 2, requested: 4),
            Self.stockPriceCheckJob(status: .completedWithIssues, phase: .finished, processed: 4, requested: 4)
        ]
        let viewModel = Self.stockPriceCheckViewModel(
            items: [initial],
            loadShoppingList: {
                listLoadCount += 1
                return Self.response(items: listLoadCount == 1 ? [initial] : [refreshed])
            },
            start: { _ in .accepted(Self.stockPriceCheckJob(status: .queued, processed: 0, requested: 4)) },
            fetch: { _ in jobs.removeFirst() },
            sleeper: { _ in }
        )
        await viewModel.loadIfNeeded()
        viewModel.setStockPriceCheckPollingAllowed(true)

        _ = await viewModel.startStockPriceCheck()
        await waitUntil { viewModel.finalStockPriceCheckSummary != nil }

        XCTAssertEqual(viewModel.stockPriceCheckJob?.status, .completedWithIssues)
        XCTAssertEqual(viewModel.finalStockPriceCheckSummary?.processedItemCount, 4)
        XCTAssertEqual(viewModel.items.first?.version, 2)
        XCTAssertGreaterThanOrEqual(listLoadCount, 2)
        XCTAssertNil(viewModel.stockPriceCheckErrorMessage)
    }

    func testStockPriceCheckPollingCancelsInBackgroundAndResumesOnReturn() async {
        let fetchGate = StockPriceCheckFetchGate()
        var fetchCount = 0
        let viewModel = Self.stockPriceCheckViewModel(
            items: [Self.item(id: 15, name: "Cereal")],
            start: { _ in .accepted(Self.stockPriceCheckJob(status: .running, processed: 0, requested: 1)) },
            fetch: { _ in
                fetchCount += 1
                if fetchCount == 1 {
                    return await fetchGate.waitForJob()
                }

                return Self.stockPriceCheckJob(
                    status: .completed,
                    phase: .finished,
                    processed: 1,
                    requested: 1
                )
            },
            sleeper: { _ in }
        )
        await viewModel.loadIfNeeded()

        viewModel.setStockPriceCheckPollingAllowed(true)
        _ = await viewModel.startStockPriceCheck()
        await fetchGate.waitUntilStarted()
        viewModel.setStockPriceCheckPollingAllowed(false)
        await fetchGate.resume(with: Self.stockPriceCheckJob(status: .running, processed: 0, requested: 1))
        await Task.yield()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertTrue(viewModel.isStockPriceCheckActive)

        viewModel.setStockPriceCheckPollingAllowed(true)
        await waitUntil { viewModel.finalStockPriceCheckSummary != nil }

        XCTAssertEqual(fetchCount, 2)
        XCTAssertFalse(viewModel.isStockPriceCheckActive)
    }

    func testStockPriceCheckPublishesFeatureReadiness() async {
        let readiness = Self.stockPriceCheckReadiness(enabled: false)
        let viewModel = Self.stockPriceCheckViewModel(
            items: [Self.item(id: 15, name: "Cereal")],
            start: { _ in .accepted(Self.stockPriceCheckJob(status: .queued)) },
            readiness: { readiness }
        )

        viewModel.setStockPriceCheckPollingAllowed(true)
        await waitUntil { viewModel.stockPriceCheckReadiness != nil }

        XCTAssertEqual(viewModel.stockPriceCheckReadiness, readiness)
        XCTAssertTrue(viewModel.isStockPriceCheckUnavailable)
        XCTAssertNil(viewModel.stockPriceCheckErrorMessage)
    }

    func testStockPriceCheckReadinessIsCachedAcrossShoppingScreenRevisits() async {
        var readinessLoadCount = 0
        let readiness = Self.stockPriceCheckReadiness(enabled: true)
        let viewModel = Self.stockPriceCheckViewModel(
            items: [Self.item(id: 15, name: "Cereal")],
            start: { _ in .accepted(Self.stockPriceCheckJob(status: .queued)) },
            readiness: {
                readinessLoadCount += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
                return readiness
            }
        )

        viewModel.setStockPriceCheckPollingAllowed(true)
        viewModel.setStockPriceCheckPollingAllowed(false)
        viewModel.setStockPriceCheckPollingAllowed(true)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(readinessLoadCount, 1)
        XCTAssertEqual(viewModel.stockPriceCheckReadiness, readiness)
    }

    func testStockPriceCheckPollingRecoversAfterTransportFailure() async {
        var fetchCount = 0
        let viewModel = Self.stockPriceCheckViewModel(
            items: [Self.item(id: 15, name: "Cereal")],
            start: { _ in .accepted(Self.stockPriceCheckJob(status: .running, processed: 0, requested: 1)) },
            fetch: { _ in
                fetchCount += 1
                if fetchCount == 1 {
                    throw APIError.transport("The network connection was lost.")
                }

                return Self.stockPriceCheckJob(
                    status: .completed,
                    phase: .finished,
                    processed: 1,
                    requested: 1
                )
            },
            sleeper: { _ in }
        )
        await viewModel.loadIfNeeded()
        viewModel.setStockPriceCheckPollingAllowed(true)

        _ = await viewModel.startStockPriceCheck()
        await waitUntil { viewModel.stockPriceCheckErrorMessage != nil }
        XCTAssertTrue(viewModel.isStockPriceCheckActive)

        viewModel.setStockPriceCheckPollingAllowed(true)
        await waitUntil { viewModel.finalStockPriceCheckSummary != nil }

        XCTAssertEqual(fetchCount, 2)
        XCTAssertNil(viewModel.stockPriceCheckErrorMessage)
        XCTAssertFalse(viewModel.isStockPriceCheckActive)
    }

    func testStockPriceCheckExplainsWhenNoItemsAreNeeded() async {
        var startCount = 0
        let viewModel = Self.stockPriceCheckViewModel(
            items: [],
            start: { _ in
                startCount += 1
                return .accepted(Self.stockPriceCheckJob(status: .queued))
            }
        )
        await viewModel.loadIfNeeded()

        let result = await viewModel.startStockPriceCheck()

        XCTAssertNil(result)
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(
            viewModel.stockPriceCheckErrorMessage,
            "Add at least one needed item before checking stock and price."
        )
    }

    func testLiveItemUpdatesRemainAuthoritativeDuringStockPriceCheck() async {
        let original = Self.item(id: 15, name: "Cereal", version: 1)
        let updated = Self.item(id: 15, name: "Granola", version: 2)
        let viewModel = Self.stockPriceCheckViewModel(
            items: [original],
            start: { _ in .accepted(Self.stockPriceCheckJob(status: .running, processed: 0, requested: 1)) }
        )
        await viewModel.loadIfNeeded()

        _ = await viewModel.startStockPriceCheck()
        await viewModel.applyLiveMessage(
            .itemUpdated(
                item: updated,
                mutationId: "live-stock-update",
                serverTime: "2026-08-02T16:00:00Z"
            )
        )

        XCTAssertEqual(viewModel.items.first?.name, "Granola")
        XCTAssertEqual(viewModel.items.first?.version, 2)
        XCTAssertTrue(viewModel.isStockPriceCheckActive)
    }

    func testShoppingListReaddStartsOnlyOnceAndAdoptsTheActiveRun() async {
        var startCount = 0
        var receivedRequest: StartShoppingListReaddRequest?
        let activeRun = Self.shoppingListReaddRun(status: .matching)
        let viewModel = Self.shoppingListReaddViewModel(
            items: [Self.item(id: 15, name: "Iced Coffee")],
            start: { request in
                startCount += 1
                receivedRequest = request
                return .active(activeRun)
            }
        )
        await viewModel.loadIfNeeded()

        let first = await viewModel.startShoppingListReadd(text: "Add two coffees")
        let second = await viewModel.startShoppingListReadd(text: "Add two coffees")

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(receivedRequest?.actor, "Josh")
        XCTAssertEqual(receivedRequest?.text, "Add two coffees")
        XCTAssertEqual(first?.id, activeRun.id)
        XCTAssertEqual(second?.id, activeRun.id)
        XCTAssertTrue(viewModel.isShoppingListReaddActive)
    }

    func testShoppingListReaddPollsProgressAndRefreshesAtTerminalState() async {
        let initial = Self.item(id: 15, name: "Iced Coffee", version: 1)
        let refreshed = Self.item(id: 15, name: "Iced Coffee", version: 2)
        var listLoadCount = 0
        var runs = [
            Self.shoppingListReaddRun(status: .applying),
            Self.shoppingListReaddRun(status: .completed, undoAvailable: true)
        ]
        let viewModel = Self.shoppingListReaddViewModel(
            items: [initial],
            loadShoppingList: {
                listLoadCount += 1
                return Self.response(items: listLoadCount == 1 ? [initial] : [refreshed])
            },
            start: { _ in .accepted(Self.shoppingListReaddRun(status: .queued)) },
            fetch: { _ in runs.removeFirst() },
            sleeper: { _ in }
        )
        await viewModel.loadIfNeeded()
        viewModel.setShoppingListReaddPollingAllowed(true)

        _ = await viewModel.startShoppingListReadd(text: "Add two coffees")
        await waitUntil { viewModel.finalShoppingListReaddSummary != nil }

        XCTAssertEqual(viewModel.shoppingListReaddRun?.status, .completed)
        XCTAssertEqual(viewModel.items.first?.version, 2)
        XCTAssertGreaterThanOrEqual(listLoadCount, 2)
        XCTAssertNil(viewModel.shoppingListReaddErrorMessage)
    }

    func testShoppingListReaddPollingCancelsInBackgroundAndResumesOnReturn() async {
        let fetchGate = ShoppingListReaddFetchGate()
        var fetchCount = 0
        let viewModel = Self.shoppingListReaddViewModel(
            items: [Self.item(id: 15, name: "Iced Coffee")],
            start: { _ in .accepted(Self.shoppingListReaddRun(status: .applying)) },
            fetch: { _ in
                fetchCount += 1
                if fetchCount == 1 {
                    return await fetchGate.waitForRun()
                }
                return Self.shoppingListReaddRun(status: .completed)
            },
            sleeper: { _ in }
        )
        await viewModel.loadIfNeeded()

        viewModel.setShoppingListReaddPollingAllowed(true)
        _ = await viewModel.startShoppingListReadd(text: "coffee")
        await fetchGate.waitUntilStarted()
        viewModel.setShoppingListReaddPollingAllowed(false)
        await fetchGate.resume(with: Self.shoppingListReaddRun(status: .applying))
        await Task.yield()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertTrue(viewModel.isShoppingListReaddActive)

        viewModel.setShoppingListReaddPollingAllowed(true)
        await waitUntil { viewModel.finalShoppingListReaddSummary != nil }

        XCTAssertEqual(fetchCount, 2)
        XCTAssertFalse(viewModel.isShoppingListReaddActive)
    }

    func testShoppingListReaddPollingRecoversAfterTransportFailure() async {
        var fetchCount = 0
        let viewModel = Self.shoppingListReaddViewModel(
            items: [Self.item(id: 15, name: "Iced Coffee")],
            start: { _ in .accepted(Self.shoppingListReaddRun(status: .applying)) },
            fetch: { _ in
                fetchCount += 1
                if fetchCount == 1 {
                    throw APIError.transport("The network connection was lost.")
                }
                return Self.shoppingListReaddRun(status: .completed)
            },
            sleeper: { _ in }
        )
        await viewModel.loadIfNeeded()
        viewModel.setShoppingListReaddPollingAllowed(true)

        _ = await viewModel.startShoppingListReadd(text: "coffee")
        await waitUntil { viewModel.shoppingListReaddErrorMessage != nil }
        XCTAssertTrue(viewModel.isShoppingListReaddActive)

        viewModel.setShoppingListReaddPollingAllowed(true)
        await waitUntil { viewModel.finalShoppingListReaddSummary != nil }

        XCTAssertEqual(fetchCount, 2)
        XCTAssertNil(viewModel.shoppingListReaddErrorMessage)
        XCTAssertFalse(viewModel.isShoppingListReaddActive)
    }

    func testShoppingListReaddPublishesReadinessAndSupportsUndoOnlyWhenAvailable() async {
        var undoCount = 0
        let unavailable = Self.shoppingListReaddReadiness(ready: false)
        let unavailableViewModel = Self.shoppingListReaddViewModel(
            items: [Self.item(id: 15, name: "Eggs")],
            start: { _ in .accepted(Self.shoppingListReaddRun(status: .queued)) },
            readiness: { unavailable }
        )
        await unavailableViewModel.loadIfNeeded()
        unavailableViewModel.setShoppingListReaddPollingAllowed(true)
        await waitUntil { unavailableViewModel.shoppingListReaddReadiness != nil }
        XCTAssertTrue(unavailableViewModel.isShoppingListReaddUnavailable)
        let unavailableResult = await unavailableViewModel.startShoppingListReadd(text: "eggs")
        XCTAssertNil(unavailableResult)
        XCTAssertEqual(unavailableViewModel.shoppingListReaddErrorMessage, "AI Shopping re-add is currently unavailable.")

        let completed = Self.shoppingListReaddRun(status: .completed, undoAvailable: true)
        let viewModel = Self.shoppingListReaddViewModel(
            items: [Self.item(id: 15, name: "Eggs")],
            start: { _ in .accepted(completed) },
            undo: { _ in
                undoCount += 1
                return Self.shoppingListReaddRun(status: .undone, undoAvailable: false)
            }
        )
        await viewModel.loadIfNeeded()
        _ = await viewModel.startShoppingListReadd(text: "eggs")
        let undone = await viewModel.undoCurrentShoppingListReadd()

        XCTAssertEqual(undoCount, 1)
        XCTAssertEqual(undone?.status, .undone)
        XCTAssertEqual(viewModel.finalShoppingListReaddSummary?.status, .undone)
        let expiredUndo = await viewModel.undoCurrentShoppingListReadd()
        XCTAssertNil(expiredUndo)
        XCTAssertEqual(undoCount, 1)
    }

    func testShoppingListReaddReadinessIsCachedAcrossShoppingScreenRevisits() async {
        var readinessLoadCount = 0
        let readiness = Self.shoppingListReaddReadiness(ready: true)
        let viewModel = Self.shoppingListReaddViewModel(
            items: [Self.item(id: 15, name: "Eggs")],
            start: { _ in .accepted(Self.shoppingListReaddRun(status: .queued)) },
            readiness: {
                readinessLoadCount += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
                return readiness
            }
        )

        viewModel.setShoppingListReaddPollingAllowed(true)
        viewModel.setShoppingListReaddPollingAllowed(false)
        viewModel.setShoppingListReaddPollingAllowed(true)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(readinessLoadCount, 1)
        XCTAssertEqual(viewModel.shoppingListReaddReadiness, readiness)
    }

    func testLiveItemUpdateSurvivesAnOlderTerminalReaddRefresh() async {
        let original = Self.item(id: 15, name: "Iced Coffee", version: 1)
        let liveUpdated = Self.item(id: 15, name: "Cold Brew", version: 2)
        let refreshGate = ShoppingListResponseGate()
        var loadCount = 0
        let terminal = Self.shoppingListReaddRun(status: .completed)
        let viewModel = Self.shoppingListReaddViewModel(
            items: [original],
            loadShoppingList: {
                loadCount += 1
                switch loadCount {
                case 1:
                    return Self.response(items: [original])
                case 2:
                    return await refreshGate.waitForResponse()
                default:
                    return Self.response(items: [liveUpdated])
                }
            },
            start: { _ in .accepted(terminal) }
        )
        await viewModel.loadIfNeeded()

        let startTask = Task { await viewModel.startShoppingListReadd(text: "coffee") }
        await refreshGate.waitUntilStarted()
        await viewModel.applyLiveMessage(
            .itemUpdated(item: liveUpdated, mutationId: "live-readd-update", serverTime: "2026-08-03T16:00:00Z")
        )
        await refreshGate.resume(with: Self.response(items: [original]))
        _ = await startTask.value

        XCTAssertEqual(viewModel.items.first?.name, "Cold Brew")
        XCTAssertEqual(viewModel.items.first?.version, 2)
    }

    func testShoppingSpeechTranscriptionExplainsDeniedPermissionWithoutStartingAudio() async {
        let runtime = FakeShoppingSpeechRuntime()
        runtime.speechAuthorization = .denied
        let service = ShoppingSpeechTranscriptionService(runtime: runtime)

        await service.startTranscribing()

        XCTAssertEqual(service.state, .denied)
        XCTAssertEqual(runtime.startCount, 0)
        XCTAssertEqual(runtime.microphonePermissionRequestCount, 0)
    }

    func testShoppingSpeechTranscriptionDoesNotRequestPermissionsUntilTapToTalk() {
        let runtime = FakeShoppingSpeechRuntime()
        _ = ShoppingSpeechTranscriptionService(runtime: runtime)

        XCTAssertEqual(runtime.speechAuthorizationRequestCount, 0)
        XCTAssertEqual(runtime.microphonePermissionRequestCount, 0)
    }

    func testShoppingSpeechTranscriptComposerPreservesEditableTypedTextBeforeSubmit() {
        XCTAssertEqual(
            ShoppingSpeechTranscriptComposer.combine(existingText: "Add milk", transcript: "and eggs"),
            "Add milk and eggs"
        )
        XCTAssertEqual(
            ShoppingSpeechTranscriptComposer.combine(existingText: "  ", transcript: "two coffees"),
            "two coffees"
        )
    }

    func testShoppingSpeechTranscriptionExplainsUnavailableRecognizer() async {
        let runtime = FakeShoppingSpeechRuntime()
        runtime.isRecognitionAvailable = false
        let service = ShoppingSpeechTranscriptionService(runtime: runtime)

        await service.startTranscribing()

        XCTAssertEqual(
            service.state,
            .unavailable("Speech recognition is unavailable for the selected language. You can still type your request.")
        )
        XCTAssertEqual(runtime.startCount, 0)
    }

    func testShoppingSpeechTranscriptionCancellationDiscardsOnlyCurrentTranscript() async {
        let runtime = FakeShoppingSpeechRuntime()
        let service = ShoppingSpeechTranscriptionService(runtime: runtime)

        await service.startTranscribing()
        runtime.emitPartialTranscript("two coffees")
        XCTAssertEqual(service.state, .listening)
        XCTAssertEqual(service.transcript, "two coffees")

        service.cancelTranscribing()

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transcript, "")
        XCTAssertEqual(runtime.cancelCount, 1)
    }

    func testShoppingSpeechTranscriptionPreservesRecognizedTextAfterStopAndNeverSubmits() async {
        let runtime = FakeShoppingSpeechRuntime()
        let service = ShoppingSpeechTranscriptionService(runtime: runtime)

        await service.startTranscribing()
        runtime.emitPartialTranscript("add eggs and milk")
        service.stopTranscribing()

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transcript, "add eggs and milk")
        XCTAssertEqual(runtime.finishCount, 1)
        XCTAssertEqual(runtime.cancelCount, 0)
    }

    func testShoppingSpeechTranscriptionHandlesAudioInterruptionAndAllowsLanguageSelection() async {
        let runtime = FakeShoppingSpeechRuntime()
        let service = ShoppingSpeechTranscriptionService(runtime: runtime)

        service.selectLanguage(identifier: "en_GB")
        XCTAssertEqual(service.selectedLanguageIdentifier, "en_GB")
        XCTAssertEqual(runtime.selectedLocaleIdentifier, "en_GB")

        await service.startTranscribing()
        runtime.completeRecognition(.failure(ShoppingSpeechRuntimeError.interrupted))

        XCTAssertEqual(service.state, .interrupted)
        XCTAssertFalse(service.isCapturing)
    }

    func testCompactOrderingPlacesMostRecentlyActiveItemsFirst() {
        let category = ShoppingCategory(id: 42, name: "Miscellaneous")
        let older = ShoppingListDisplayItem(
            item: Self.item(
                id: 10,
                name: "Older",
                updated: "2026-07-11T06:00:00Z"
            ),
            category: category
        )
        let newer = ShoppingListDisplayItem(
            item: Self.item(
                id: 11,
                name: "Newer",
                updated: "2026-07-11T08:00:00Z"
            ),
            category: category
        )
        let sameTimeHigherVersion = ShoppingListDisplayItem(
            item: Self.item(
                id: 12,
                name: "Higher version",
                version: 3,
                updated: "2026-07-11T08:00:00Z"
            ),
            category: category
        )

        let sorted = [older, newer, sameTimeHigherVersion]
            .sorted(by: ShoppingListDisplayItem.isMoreRecentlyActive)

        XCTAssertEqual(sorted.map(\.id), [12, 11, 10])
    }

    func testStoreListingPresentationPrefersFreshVerifiedListingsWithoutDuplicateStores() {
        let manualTarget = Self.listing(
            storeId: 1,
            storeName: "Target",
            source: "manual",
            price: ShoppingStoreListingPrice(regular: 8.99, promo: nil)
        )
        let olderVerifiedTarget = Self.listing(
            storeId: 1,
            storeName: "Target",
            source: "target.com",
            address: "1365 Sgt Jon Stiles Dr, Highlands Ranch, CO",
            price: ShoppingStoreListingPrice(regular: 5.49, promo: 4.99),
            availability: ShoppingStoreListingAvailability(status: "in_stock", checkedAt: "2026-08-02T15:00:00Z")
        )
        let freshestVerifiedTarget = Self.listing(
            storeId: 1,
            storeName: "Target",
            source: "target.com",
            address: "1365 Sgt Jon Stiles Dr, Highlands Ranch, CO",
            price: ShoppingStoreListingPrice(regular: 4.29, promo: 3.79),
            availability: ShoppingStoreListingAvailability(status: "low_stock", checkedAt: "2026-08-02T16:00:00Z")
        )
        let manualKingSoopers = Self.listing(
            storeId: 2,
            storeName: "King Soopers",
            source: "manual",
            price: ShoppingStoreListingPrice(regular: 6.49, promo: nil)
        )
        let verifiedKingSoopers = Self.listing(
            storeId: 2,
            storeName: "King Soopers",
            source: "kingsoopers.com",
            address: "2205 W Wildcat Reserve Pkwy, Highlands Ranch, CO",
            price: ShoppingStoreListingPrice(regular: 3.99, promo: nil),
            availability: ShoppingStoreListingAvailability(status: "out_of_stock", checkedAt: "2026-08-02T16:05:00Z")
        )

        let displayed = ShoppingStoreListingPresentation.coalescedListings(from: [
            manualTarget,
            olderVerifiedTarget,
            freshestVerifiedTarget,
            manualKingSoopers,
            verifiedKingSoopers,
        ])

        XCTAssertEqual(displayed.count, 2)
        XCTAssertEqual(displayed.map { ShoppingStoreListingPresentation.storeName(for: $0) }, ["Target", "King Soopers"])
        XCTAssertEqual(ShoppingStoreListingPresentation.priceText(for: displayed[0]), "$3.79")
        XCTAssertEqual(ShoppingStoreListingPresentation.priceText(for: displayed[1]), "$3.99")
        XCTAssertEqual(ShoppingStoreListingPresentation.availabilityLabel(for: displayed[0]), "Low stock")
        XCTAssertEqual(ShoppingStoreListingPresentation.availabilityLabel(for: displayed[1]), "Out of stock")
    }

    func testStoreListingPresentationUsesAllNormalizedAvailabilityTones() {
        let listings: [(ShoppingItemStoreListing, StatusBadgeTone)] = [
            (Self.listing(availability: ShoppingStoreListingAvailability(status: "in_stock")), .success),
            (Self.listing(availability: ShoppingStoreListingAvailability(status: "low_stock")), .warning),
            (Self.listing(availability: ShoppingStoreListingAvailability(status: "out_of_stock")), .critical),
            (Self.listing(availability: ShoppingStoreListingAvailability(status: "unknown")), .neutral),
        ]

        for (listing, expectedTone) in listings {
            XCTAssertEqual(ShoppingStoreListingPresentation.availabilityTone(for: listing), expectedTone)
        }

        let legacyInventoryOnly = Self.listing(
            availability: nil,
            inventory: ["stockLevel": .string("LOW")]
        )
        XCTAssertEqual(ShoppingStoreListingPresentation.availabilityTone(for: legacyInventoryOnly), .neutral)
        XCTAssertEqual(ShoppingStoreListingPresentation.availabilityLabel(for: legacyInventoryOnly), "Availability unknown")
    }

    func testStoreListingPresentationLeavesMissingValuesUnavailableAndDescribesFreshnessAccessibly() {
        let missing = Self.listing(
            availability: ShoppingStoreListingAvailability(status: "unknown")
        )
        XCTAssertNil(ShoppingStoreListingPresentation.priceText(for: missing))
        XCTAssertNil(ShoppingStoreListingPresentation.locationText(for: missing))
        XCTAssertNil(ShoppingStoreListingPresentation.freshnessText(for: missing, now: Date(timeIntervalSince1970: 1_000)))
        XCTAssertEqual(
            ShoppingStoreListingPresentation.accessibilityLabel(for: missing, now: Date(timeIntervalSince1970: 1_000)),
            "Target, Availability unknown, freshness unavailable"
        )

        let stale = Self.listing(
            aisle: ShoppingStoreListingAisle(display: nil, description: "Aisle 12", number: nil, shelfNumber: nil, raw: nil),
            price: ShoppingStoreListingPrice(regular: 7.99, promo: nil),
            availability: ShoppingStoreListingAvailability(status: "in_stock", checkedAt: "2026-07-30T16:00:00Z")
        )
        let now = ISO8601DateFormatter().date(from: "2026-08-02T16:00:00Z")!
        XCTAssertEqual(ShoppingStoreListingPresentation.locationText(for: stale), "Aisle 12")
        XCTAssertEqual(ShoppingStoreListingPresentation.freshnessText(for: stale, now: now), "Last checked 3d ago")
        XCTAssertEqual(
            ShoppingStoreListingPresentation.accessibilityLabel(for: stale, now: now),
            "Target, In stock, location Aisle 12, price $7.99, Last checked 3d ago"
        )
    }

    func testDetailedAndCompactAccessibilityLabelsIncludeVerifiedStoreDetails() {
        let listing = Self.listing(
            source: "target.com",
            address: "1365 Sgt Jon Stiles Dr, Highlands Ranch, CO",
            aisle: ShoppingStoreListingAisle(display: "A12", description: nil, number: nil, shelfNumber: nil, raw: nil),
            price: ShoppingStoreListingPrice(regular: 4.29, promo: nil),
            availability: ShoppingStoreListingAvailability(status: "in_stock", checkedAt: "2026-08-02T16:00:00Z")
        )
        let displayItem = ShoppingListDisplayItem(
            item: ShoppingListItem(
                id: 44,
                name: "Coffee",
                brand: nil,
                quantity: 1,
                notes: nil,
                purchased: false,
                created: nil,
                updated: nil,
                categoryId: 1,
                storeListings: [listing]
            ),
            category: ShoppingCategory(id: 1, name: "Pantry")
        )

        XCTAssertTrue(displayItem.accessibilityLabel.contains("Target, In stock, location A12, price $4.29"))
        XCTAssertTrue(displayItem.compactAccessibilityLabel.contains("Target, In stock, location A12, price $4.29"))
    }

    func testDismissingFinalStockPriceCheckSummaryClearsOnlyTheTerminalPresentation() async {
        let completed = Self.stockPriceCheckJob(
            status: .completed,
            processed: 1,
            requested: 1
        )
        let viewModel = Self.stockPriceCheckViewModel(
            items: [Self.item(id: 55, name: "Coffee")],
            start: { _ in .accepted(completed) }
        )
        await viewModel.loadIfNeeded()

        _ = await viewModel.startStockPriceCheck()
        XCTAssertEqual(viewModel.finalStockPriceCheckSummary?.id, completed.id)

        viewModel.dismissFinalStockPriceCheckSummary()
        XCTAssertNil(viewModel.finalStockPriceCheckSummary)
        XCTAssertEqual(viewModel.stockPriceCheckJob?.id, completed.id)
    }

    private static func response(
        items: [ShoppingListItem],
        activeTrip: ShoppingTrip? = nil
    ) -> ShoppingListResponse {
        ShoppingListResponse(
            ok: true,
            items: items,
            stores: [],
            categories: [],
            activeTrip: activeTrip,
            generatedAt: "2026-07-01T17:30:00Z"
        )
    }

    private static func tripViewModel(
        items: [ShoppingListItem],
        start: @escaping ShoppingListViewModel.ShoppingTripStarter = { request in
            ShoppingTripMutationResponse(
                ok: true,
                trip: trip(),
                activeTrip: trip(),
                mutationId: request.mutationId,
                displayDisposition: nil,
                generatedAt: nil
            )
        }
    ) -> ShoppingListViewModel {
        ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: { response(items: items) },
            lookupShoppingListItem: { name in ShoppingListItemLookupResponse(ok: true, query: name, match: nil) },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, _ in throw APIError.transport("Unused") },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") },
            startShoppingTrip: start
        )
    }

    private static func stockPriceCheckViewModel(
        items: [ShoppingListItem],
        loadShoppingList: ShoppingListViewModel.ShoppingListLoader? = nil,
        start: @escaping ShoppingListViewModel.ShoppingStockPriceCheckStarter,
        fetch: @escaping ShoppingListViewModel.ShoppingStockPriceCheckLoader = { _ in
            throw APIError.transport("Unused")
        },
        readiness: @escaping ShoppingListViewModel.ShoppingStockPriceCheckReadinessLoader = {
            throw APIError.transport("Unused")
        },
        sleeper: @escaping ShoppingListViewModel.ShoppingStockPriceCheckSleeper = { _ in }
    ) -> ShoppingListViewModel {
        ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: loadShoppingList ?? { response(items: items) },
            lookupShoppingListItem: { name in ShoppingListItemLookupResponse(ok: true, query: name, match: nil) },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, _ in throw APIError.transport("Unused") },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") },
            startShoppingStockPriceCheck: start,
            fetchShoppingStockPriceCheck: fetch,
            fetchShoppingStockPriceCheckReadiness: readiness,
            stockPriceCheckSleep: sleeper
        )
    }

    private static func stockPriceCheckJob(
        id: String = "stock-check-1",
        status: ShoppingStockPriceCheckStatus,
        phase: ShoppingStockPriceCheckPhase = .checkingStores,
        processed: Int = 0,
        requested: Int = 1
    ) -> ShoppingStockPriceCheckSummary {
        ShoppingStockPriceCheckSummary(
            ok: true,
            id: id,
            status: status,
            phase: phase,
            requestedItemCount: requested,
            processedItemCount: processed,
            updatedItemCount: processed,
            unmatchedItemCount: 0,
            failedItemCount: 0,
            skippedStaleItemCount: 0,
            submittedAt: "2026-08-02T16:00:00Z",
            startedAt: "2026-08-02T16:00:01Z",
            finishedAt: status == .completed || status == .completedWithIssues || status == .failed
                ? "2026-08-02T16:00:02Z"
                : nil,
            failureCode: nil,
            message: nil
        )
    }

    private static func stockPriceCheckReadiness(enabled: Bool) -> ShoppingStockPriceCheckReadiness {
        ShoppingStockPriceCheckReadiness(
            ok: enabled,
            enabled: enabled,
            checks: ShoppingStockPriceCheckReadiness.Checks(
                persistence: ShoppingStockPriceCheckReadiness.Persistence(
                    ok: enabled,
                    configured: enabled,
                    code: enabled ? nil : "site_scope_unavailable"
                ),
                fixedStoreScope: ShoppingStockPriceCheckReadiness.FixedStoreScope(
                    ok: enabled,
                    targetHighlandsRanch: enabled,
                    kingSoopersWildcatReserve: enabled,
                    allowedHosts: enabled,
                    allowedMethods: enabled
                ),
                codexRuntime: ShoppingStockPriceCheckReadiness.CodexRuntime(
                    ok: enabled,
                    enabled: enabled,
                    code: enabled ? nil : "site_scope_unavailable"
                )
            )
        )
    }

    private static func shoppingListReaddViewModel(
        items: [ShoppingListItem],
        loadShoppingList: ShoppingListViewModel.ShoppingListLoader? = nil,
        start: @escaping ShoppingListViewModel.ShoppingListReaddStarter,
        fetch: @escaping ShoppingListViewModel.ShoppingListReaddLoader = { _ in
            throw APIError.transport("Unused")
        },
        undo: @escaping ShoppingListViewModel.ShoppingListReaddUndoer = { _ in
            throw APIError.transport("Unused")
        },
        readiness: @escaping ShoppingListViewModel.ShoppingListReaddReadinessLoader = {
            throw APIError.transport("Unused")
        },
        sleeper: @escaping ShoppingListViewModel.ShoppingListReaddSleeper = { _ in }
    ) -> ShoppingListViewModel {
        ShoppingListViewModel(
            currentActorName: "Josh",
            loadShoppingList: loadShoppingList ?? { response(items: items) },
            lookupShoppingListItem: { name in ShoppingListItemLookupResponse(ok: true, query: name, match: nil) },
            createShoppingListItem: { _ in throw APIError.transport("Unused") },
            updateShoppingListItem: { _, _ in throw APIError.transport("Unused") },
            deleteShoppingListItem: { _, _, _ in throw APIError.transport("Unused") },
            startShoppingListReadd: start,
            fetchShoppingListReadd: fetch,
            undoShoppingListReadd: undo,
            fetchShoppingListReaddReadiness: readiness,
            shoppingListReaddSleep: sleeper
        )
    }

    private static func shoppingListReaddRun(
        id: String = "readd-run-1",
        status: ShoppingListReaddRunStatus,
        undoAvailable: Bool = false
    ) -> ShoppingListReaddSummary {
        ShoppingListReaddSummary(
            ok: true,
            id: id,
            status: status,
            operations: [],
            unmatched: [],
            undo: ShoppingListReaddUndoAvailability(
                available: undoAvailable,
                expiresAt: undoAvailable ? "2026-08-03T12:10:00.000Z" : nil
            ),
            submittedAt: "2026-08-03T12:00:00.000Z",
            startedAt: "2026-08-03T12:00:01.000Z",
            finishedAt: status == .completed || status == .completedWithIssues || status == .failed || status == .undone
                ? "2026-08-03T12:00:02.000Z"
                : nil
        )
    }

    private static func shoppingListReaddReadiness(ready: Bool) -> ShoppingListReaddReadiness {
        ShoppingListReaddReadiness(
            ready: ready,
            matcherRuntime: ShoppingListReaddReadiness.Check(ready: ready, code: ready ? nil : "matcher_unavailable"),
            authentication: ShoppingListReaddReadiness.Check(ready: ready, code: ready ? nil : "authentication_unavailable"),
            persistence: ShoppingListReaddReadiness.Check(ready: ready, code: ready ? nil : "persistence_unavailable")
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }

            await Task.yield()
        }

        XCTFail("Timed out waiting for the expected state.", file: file, line: line)
    }

    private static func trip(
        version: Int = 1,
        pickedUpCount: Int = 0,
        remainingCount: Int = 1
    ) -> ShoppingTrip {
        ShoppingTrip(
            id: "fca7f84a-8527-4a58-90b5-a78e4cde5b16",
            status: "active",
            startedBy: "Josh",
            startedAt: "2026-07-11T18:00:00.000Z",
            endedBy: nil,
            endedAt: nil,
            pickedUpCount: pickedUpCount,
            remainingCount: remainingCount,
            totalItemCount: 1,
            estimatedTotalCents: 0,
            pricedPickedItemCount: 0,
            unpricedPickedItemCount: 0,
            currencyCode: "USD",
            version: version,
            activityUpdatedAtEpochSeconds: nil
        )
    }

    private static func item(
        id: Int,
        name: String,
        version: Int = 1,
        updated: String = "2026-07-01T17:00:00Z"
    ) -> ShoppingListItem {
        ShoppingListItem(
            id: id,
            name: name,
            brand: nil,
            quantity: 1,
            notes: nil,
            purchased: false,
            created: "2026-07-01T17:00:00Z",
            updated: updated,
            version: version,
            categoryId: nil
        )
    }

    private static func listing(
        storeId: Int? = 1,
        storeName: String? = "Target",
        source: String? = "manual",
        address: String? = nil,
        aisle: ShoppingStoreListingAisle? = nil,
        price: ShoppingStoreListingPrice? = nil,
        availability: ShoppingStoreListingAvailability? = nil,
        inventory: [String: JSONValue]? = nil
    ) -> ShoppingItemStoreListing {
        ShoppingItemStoreListing(
            storeId: storeId,
            storeName: storeName,
            source: source,
            selectedStoreAddress: address,
            aisle: aisle,
            price: price,
            inventory: inventory,
            availability: availability
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

private actor ShoppingListResponseGate {
    private var responseContinuation: CheckedContinuation<ShoppingListResponse, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false

    func waitForResponse() async -> ShoppingListResponse {
        hasStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations = []

        return await withCheckedContinuation { continuation in
            responseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func resume(with response: ShoppingListResponse) {
        responseContinuation?.resume(returning: response)
        responseContinuation = nil
    }
}

private actor ShoppingListMutationResponseGate {
    private var responseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false

    func waitForResponse(_ response: ShoppingListMutationResponse) async -> ShoppingListMutationResponse {
        hasStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations = []

        await withCheckedContinuation { continuation in
            responseContinuation = continuation
        }

        return response
    }

    func waitUntilStarted() async {
        guard !hasStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func resume() {
        responseContinuation?.resume()
        responseContinuation = nil
    }
}

private actor StockPriceCheckStartGate {
    private var jobContinuation: CheckedContinuation<ShoppingStockPriceCheckSummary, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false

    func waitForJob() async -> ShoppingStockPriceCheckSummary {
        hasStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations = []

        return await withCheckedContinuation { continuation in
            jobContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func resume(with job: ShoppingStockPriceCheckSummary) {
        jobContinuation?.resume(returning: job)
        jobContinuation = nil
    }
}

private actor StockPriceCheckFetchGate {
    private var jobContinuation: CheckedContinuation<ShoppingStockPriceCheckSummary, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false

    func waitForJob() async -> ShoppingStockPriceCheckSummary {
        hasStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations = []

        return await withCheckedContinuation { continuation in
            jobContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func resume(with job: ShoppingStockPriceCheckSummary) {
        jobContinuation?.resume(returning: job)
        jobContinuation = nil
    }
}

private actor ShoppingListReaddFetchGate {
    private var runContinuation: CheckedContinuation<ShoppingListReaddSummary, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false

    func waitForRun() async -> ShoppingListReaddSummary {
        hasStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations = []

        return await withCheckedContinuation { continuation in
            runContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func resume(with run: ShoppingListReaddSummary) {
        runContinuation?.resume(returning: run)
        runContinuation = nil
    }
}

@MainActor
private final class FakeShoppingSpeechRuntime: ShoppingSpeechRecognitionRuntime {
    var isRecognitionAvailable = true
    var supportsOnDeviceRecognition = true
    var speechAuthorization: ShoppingSpeechAuthorization = .authorized
    var microphonePermissionGranted = true
    private(set) var selectedLocaleIdentifier: String?
    private(set) var speechAuthorizationRequestCount = 0
    private(set) var microphonePermissionRequestCount = 0
    private(set) var startCount = 0
    private(set) var finishCount = 0
    private(set) var cancelCount = 0
    private var partialTranscriptHandler: ((String) -> Void)?
    private var completionHandler: ((Result<Void, Error>) -> Void)?

    func selectLanguage(locale: Locale) {
        selectedLocaleIdentifier = locale.identifier
    }

    func requestSpeechAuthorization() async -> ShoppingSpeechAuthorization {
        speechAuthorizationRequestCount += 1
        return speechAuthorization
    }

    func requestMicrophonePermission() async -> Bool {
        microphonePermissionRequestCount += 1
        return microphonePermissionGranted
    }

    func startRecognition(
        onPartialTranscript: @escaping (String) -> Void,
        onCompletion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        startCount += 1
        partialTranscriptHandler = onPartialTranscript
        completionHandler = onCompletion
    }

    func finishRecognition() {
        finishCount += 1
        partialTranscriptHandler = nil
        completionHandler = nil
    }

    func cancelRecognition() {
        cancelCount += 1
        partialTranscriptHandler = nil
        completionHandler = nil
    }

    func emitPartialTranscript(_ transcript: String) {
        partialTranscriptHandler?(transcript)
    }

    func completeRecognition(_ result: Result<Void, Error>) {
        completionHandler?(result)
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
