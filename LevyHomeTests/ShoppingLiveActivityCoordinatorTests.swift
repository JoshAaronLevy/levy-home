import ActivityKit
import XCTest
@testable import LevyHome

@MainActor
final class ShoppingLiveActivityCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_752_259_200)

    func testDisabledAuthorizationReturnsNonfatalUnavailableResult() async {
        let client = FakeShoppingLiveActivityClient(activitiesAreEnabled: false)
        let coordinator = ShoppingLiveActivityCoordinator(
            activityClient: client,
            now: { self.now }
        )

        let result = await coordinator.startSampleActivity()

        XCTAssertEqual(result.kind, .unavailable)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(coordinator.hasActiveActivity)
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertTrue(result.message.contains("Live Activities are turned off"))
    }

    func testStartRequestsExpectedLocalSampleAndTrimsResidentName() async throws {
        let client = FakeShoppingLiveActivityClient()
        let coordinator = ShoppingLiveActivityCoordinator(
            activityClient: client,
            now: { self.now }
        )

        let result = await coordinator.startSampleActivity(startedByName: "  Mallory  ")

        XCTAssertEqual(result.kind, .started)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.activityID, client.requestedSession.id)
        XCTAssertTrue(coordinator.hasActiveActivity)
        XCTAssertEqual(client.requestCount, 1)

        let attributes = try XCTUnwrap(client.requestedAttributes)
        XCTAssertEqual(attributes.tripID, ShoppingLiveActivityCoordinator.sampleTripID)
        XCTAssertEqual(attributes.startedByName, "Mallory")
        XCTAssertEqual(attributes.startedAtEpochSeconds, Int(now.timeIntervalSince1970))

        let state = try XCTUnwrap(client.requestedInitialState)
        XCTAssertEqual(state.status, "active")
        XCTAssertEqual(state.pickedUpCount, 3)
        XCTAssertEqual(state.remainingCount, 7)
        XCTAssertEqual(state.estimatedTotalCents, 2_550)
        XCTAssertEqual(state.currencyCode, "USD")
        XCTAssertEqual(state.stateVersion, 1)
    }

    func testStartRecoversExistingSampleWithoutRequestingDuplicate() async {
        let existing = FakeShoppingLiveActivitySession(
            id: "existing-activity",
            tripID: ShoppingLiveActivityCoordinator.sampleTripID,
            activityState: .active,
            stateVersion: 8
        )
        let client = FakeShoppingLiveActivityClient(activities: [existing])
        let coordinator = ShoppingLiveActivityCoordinator(activityClient: client)

        let result = await coordinator.startSampleActivity()

        XCTAssertEqual(result.kind, .recovered)
        XCTAssertEqual(result.activityID, existing.id)
        XCTAssertEqual(coordinator.activeActivityID, existing.id)
        XCTAssertEqual(client.requestCount, 0)
    }

    @available(iOS 26.0, *)
    func testPendingSampleIsTreatedAsActiveForStartDedupe() async {
        let pending = FakeShoppingLiveActivitySession(
            id: "pending-activity",
            tripID: ShoppingLiveActivityCoordinator.sampleTripID,
            activityState: .pending,
            stateVersion: 1
        )
        let client = FakeShoppingLiveActivityClient(activities: [pending])
        let coordinator = ShoppingLiveActivityCoordinator(activityClient: client)

        let result = await coordinator.startSampleActivity()

        XCTAssertEqual(result.kind, .recovered)
        XCTAssertEqual(result.activityID, pending.id)
        XCTAssertEqual(client.requestCount, 0)
    }

    func testStartFailureLeavesNoActiveSample() async {
        let client = FakeShoppingLiveActivityClient()
        client.requestError = FakeError.requestFailed
        let coordinator = ShoppingLiveActivityCoordinator(activityClient: client)

        let result = await coordinator.startSampleActivity()

        XCTAssertEqual(result.kind, .failed)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(coordinator.hasActiveActivity)
        XCTAssertTrue(result.message.contains("could not start"))
    }

    func testRepeatedUpdatesCycleEveryLayoutStressCaseWithIncreasingVersions() async {
        let existing = FakeShoppingLiveActivitySession(
            id: "sample-activity",
            tripID: ShoppingLiveActivityCoordinator.sampleTripID,
            activityState: .active,
            stateVersion: 1
        )
        let client = FakeShoppingLiveActivityClient(activities: [existing])
        let coordinator = ShoppingLiveActivityCoordinator(
            activityClient: client,
            now: { self.now }
        )

        for _ in 0..<4 {
            let result = await coordinator.updateSampleActivity()
            XCTAssertEqual(result.kind, .updated)
        }

        XCTAssertEqual(existing.updatedStates.map(\.remainingCount), [0, 3, 99, 999])
        XCTAssertEqual(existing.updatedStates.map(\.estimatedTotalCents), [0, 2_550, 99_999, 999_999])
        XCTAssertEqual(existing.updatedStates.map(\.stateVersion), [2, 3, 4, 5])
        XCTAssertEqual(existing.updatedStates.last?.unpricedPickedItemCount, 1)
    }

    func testEndUsesFinalStateAndFifteenMinuteDismissal() async throws {
        let existing = FakeShoppingLiveActivitySession(
            id: "sample-activity",
            tripID: ShoppingLiveActivityCoordinator.sampleTripID,
            activityState: .active,
            stateVersion: 5
        )
        let client = FakeShoppingLiveActivityClient(activities: [existing])
        let coordinator = ShoppingLiveActivityCoordinator(
            activityClient: client,
            now: { self.now }
        )

        let result = await coordinator.endSampleActivity()

        XCTAssertEqual(result.kind, .ended)
        XCTAssertFalse(coordinator.hasActiveActivity)
        let finalState = try XCTUnwrap(existing.endedState)
        XCTAssertTrue(finalState.isCompleted)
        XCTAssertEqual(finalState.pickedUpCount, 8)
        XCTAssertEqual(finalState.remainingCount, 2)
        XCTAssertEqual(finalState.estimatedTotalCents, 6_742)
        XCTAssertEqual(finalState.stateVersion, 6)
        XCTAssertEqual(
            existing.dismissalDate,
            now.addingTimeInterval(ShoppingLiveActivityCoordinator.completedActivityVisibilityDuration)
        )
    }

    func testUpdateAndEndWithoutSampleReturnUsefulFailures() async {
        let coordinator = ShoppingLiveActivityCoordinator(
            activityClient: FakeShoppingLiveActivityClient()
        )

        let updateResult = await coordinator.updateSampleActivity()
        let endResult = await coordinator.endSampleActivity()

        XCTAssertEqual(updateResult.kind, .failed)
        XCTAssertTrue(updateResult.message.contains("Start one before updating"))
        XCTAssertEqual(endResult.kind, .failed)
        XCTAssertTrue(endResult.message.contains("Start one before ending"))
    }
}

@MainActor
private final class FakeShoppingLiveActivityClient: ShoppingLiveActivityClient {
    var activitiesAreEnabled: Bool
    var activities: [any ShoppingLiveActivitySession]
    var requestError: Error?
    private(set) var requestCount = 0
    private(set) var requestedAttributes: ShoppingTripActivityAttributes?
    private(set) var requestedInitialState: ShoppingTripActivityState?

    let requestedSession = FakeShoppingLiveActivitySession(
        id: "new-activity",
        tripID: ShoppingLiveActivityCoordinator.sampleTripID,
        activityState: .active,
        stateVersion: 1
    )

    init(
        activitiesAreEnabled: Bool = true,
        activities: [any ShoppingLiveActivitySession] = []
    ) {
        self.activitiesAreEnabled = activitiesAreEnabled
        self.activities = activities
    }

    func requestActivity(
        attributes: ShoppingTripActivityAttributes,
        initialState: ShoppingTripActivityState
    ) throws -> any ShoppingLiveActivitySession {
        requestCount += 1
        requestedAttributes = attributes
        requestedInitialState = initialState

        if let requestError {
            throw requestError
        }

        activities.append(requestedSession)
        return requestedSession
    }
}

@MainActor
private final class FakeShoppingLiveActivitySession: ShoppingLiveActivitySession {
    let id: String
    let tripID: String
    var activityState: ActivityState
    private(set) var stateVersion: Int
    private(set) var updatedStates: [ShoppingTripActivityState] = []
    private(set) var endedState: ShoppingTripActivityState?
    private(set) var dismissalDate: Date?

    init(
        id: String,
        tripID: String,
        activityState: ActivityState,
        stateVersion: Int
    ) {
        self.id = id
        self.tripID = tripID
        self.activityState = activityState
        self.stateVersion = stateVersion
    }

    func update(to state: ShoppingTripActivityState) async {
        updatedStates.append(state)
        stateVersion = state.stateVersion
    }

    func end(
        with finalState: ShoppingTripActivityState,
        dismissalDate: Date
    ) async {
        endedState = finalState
        self.dismissalDate = dismissalDate
        stateVersion = finalState.stateVersion
        activityState = .ended
    }
}

private enum FakeError: LocalizedError {
    case requestFailed

    var errorDescription: String? {
        "Synthetic request failure"
    }
}
