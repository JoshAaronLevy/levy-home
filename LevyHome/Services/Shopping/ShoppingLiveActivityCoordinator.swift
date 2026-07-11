import ActivityKit
import Combine
import Foundation

@MainActor
protocol ShoppingLiveActivityClient {
    var activitiesAreEnabled: Bool { get }
    var activities: [any ShoppingLiveActivitySession] { get }

    func requestActivity(
        attributes: ShoppingTripActivityAttributes,
        initialState: ShoppingTripActivityState
    ) throws -> any ShoppingLiveActivitySession
}

@MainActor
protocol ShoppingLiveActivitySession: AnyObject {
    var id: String { get }
    var tripID: String { get }
    var activityState: ActivityState { get }
    var stateVersion: Int { get }

    func update(to state: ShoppingTripActivityState) async
    func end(
        with finalState: ShoppingTripActivityState,
        dismissalDate: Date
    ) async
}

@MainActor
final class ActivityKitShoppingLiveActivityClient: ShoppingLiveActivityClient {
    private let authorizationInfo: ActivityAuthorizationInfo

    init(authorizationInfo: ActivityAuthorizationInfo = ActivityAuthorizationInfo()) {
        self.authorizationInfo = authorizationInfo
    }

    var activitiesAreEnabled: Bool {
        authorizationInfo.areActivitiesEnabled
    }

    var activities: [any ShoppingLiveActivitySession] {
        Activity<ShoppingTripActivityAttributes>.activities.map(
            ActivityKitShoppingLiveActivitySession.init
        )
    }

    func requestActivity(
        attributes: ShoppingTripActivityAttributes,
        initialState: ShoppingTripActivityState
    ) throws -> any ShoppingLiveActivitySession {
        let content = ActivityContent(
            state: initialState,
            staleDate: nil,
            relevanceScore: 1
        )
        let activity = try Activity<ShoppingTripActivityAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil,
            style: .standard
        )
        return ActivityKitShoppingLiveActivitySession(activity: activity)
    }
}

@MainActor
private final class ActivityKitShoppingLiveActivitySession: ShoppingLiveActivitySession {
    private let activity: Activity<ShoppingTripActivityAttributes>

    init(activity: Activity<ShoppingTripActivityAttributes>) {
        self.activity = activity
    }

    var id: String {
        activity.id
    }

    var tripID: String {
        activity.attributes.tripID
    }

    var activityState: ActivityState {
        activity.activityState
    }

    var stateVersion: Int {
        activity.content.state.stateVersion
    }

    func update(to state: ShoppingTripActivityState) async {
        let content = ActivityContent(
            state: state,
            staleDate: nil,
            relevanceScore: 1
        )
        await activity.update(content)
    }

    func end(
        with finalState: ShoppingTripActivityState,
        dismissalDate: Date
    ) async {
        let content = ActivityContent(
            state: finalState,
            staleDate: nil,
            relevanceScore: 0
        )
        await activity.end(
            content,
            dismissalPolicy: .after(dismissalDate)
        )
    }
}

enum ShoppingLiveActivityOperationKind: Equatable, Sendable {
    case started
    case recovered
    case updated
    case ended
    case unavailable
    case failed
}

struct ShoppingLiveActivityOperationResult: Equatable, Sendable {
    let kind: ShoppingLiveActivityOperationKind
    let message: String
    let activityID: String?

    var succeeded: Bool {
        switch kind {
        case .started, .recovered, .updated, .ended:
            return true
        case .unavailable, .failed:
            return false
        }
    }
}

@MainActor
final class ShoppingLiveActivityCoordinator: ObservableObject {
    static let sampleTripID = "stage-1-local-shopping-sample"
    static let completedActivityVisibilityDuration: TimeInterval = 15 * 60

    @Published private(set) var activitiesAreEnabled: Bool
    @Published private(set) var activeActivityID: String?
    @Published private(set) var isRunningOperation = false
    @Published private(set) var statusMessage: String
    @Published private(set) var lastResult: ShoppingLiveActivityOperationResult?

    private let activityClient: any ShoppingLiveActivityClient
    private let now: () -> Date
    private var activeActivity: (any ShoppingLiveActivitySession)?
    private var nextSampleUpdateIndex = 0
    private var sampleStateVersion: Int

    init(
        activityClient: (any ShoppingLiveActivityClient)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedActivityClient = activityClient ?? ActivityKitShoppingLiveActivityClient()
        self.activityClient = resolvedActivityClient
        self.now = now
        activitiesAreEnabled = resolvedActivityClient.activitiesAreEnabled

        let recoveredActivity = resolvedActivityClient.activities.first { activity in
            activity.tripID == Self.sampleTripID && Self.isDisplayActive(activity)
        }
        activeActivity = recoveredActivity
        activeActivityID = recoveredActivity?.id
        sampleStateVersion = recoveredActivity?.stateVersion ?? 0
        statusMessage = recoveredActivity == nil
            ? "No sample shopping Live Activity is running."
            : "Recovered the sample shopping Live Activity."
    }

    var hasActiveActivity: Bool {
        activeActivityID != nil
    }

    func refreshState() {
        activitiesAreEnabled = activityClient.activitiesAreEnabled
        activeActivity = currentSampleActivity()
        activeActivityID = activeActivity?.id
        sampleStateVersion = activeActivity?.stateVersion ?? 0

        if !activitiesAreEnabled {
            statusMessage = Self.activitiesDisabledMessage
        } else if activeActivity != nil {
            statusMessage = "A sample shopping Live Activity is running."
        } else {
            statusMessage = "No sample shopping Live Activity is running."
        }
    }

    @discardableResult
    func startSampleActivity(startedByName: String = "Josh") async -> ShoppingLiveActivityOperationResult {
        guard beginOperation() else {
            return publishBusyResult()
        }
        defer { isRunningOperation = false }

        activitiesAreEnabled = activityClient.activitiesAreEnabled

        guard activitiesAreEnabled else {
            return publish(
                kind: .unavailable,
                message: Self.activitiesDisabledMessage
            )
        }

        if let activity = currentActivity() {
            return publish(
                kind: .recovered,
                message: "The sample shopping Live Activity is already running.",
                activityID: activity.id
            )
        }

        let timestamp = Self.epochSeconds(from: now())
        let attributes = ShoppingTripActivityAttributes(
            tripID: Self.sampleTripID,
            startedByName: Self.nonemptyName(startedByName),
            startedAtEpochSeconds: timestamp
        )
        do {
            let activity = try activityClient.requestActivity(
                attributes: attributes,
                initialState: Self.sampleInitialState(updatedAtEpochSeconds: timestamp)
            )
            activeActivity = activity
            activeActivityID = activity.id
            nextSampleUpdateIndex = 0
            sampleStateVersion = 1

            return publish(
                kind: .started,
                message: "Started the sample shopping Live Activity. Lock this iPhone to inspect it.",
                activityID: activity.id
            )
        } catch {
            activeActivity = nil
            activeActivityID = nil
            return publish(
                kind: .failed,
                message: "The sample shopping Live Activity could not start: \(error.localizedDescription)"
            )
        }
    }

    @discardableResult
    func updateSampleActivity() async -> ShoppingLiveActivityOperationResult {
        let timestamp = Self.epochSeconds(from: now())
        let scenarios = Self.sampleUpdateScenarios(
            updatedAtEpochSeconds: timestamp,
            stateVersion: sampleStateVersion + 1
        )
        let scenario = scenarios[nextSampleUpdateIndex % scenarios.count]
        let result = await updateSampleActivity(
            to: scenario.state,
            successMessage: "Updated the sample to \(scenario.description)."
        )

        if result.kind == .updated {
            nextSampleUpdateIndex = (nextSampleUpdateIndex + 1) % scenarios.count
        }

        return result
    }

    @discardableResult
    func updateSampleActivity(
        to state: ShoppingTripActivityState,
        successMessage: String = "Updated the sample shopping Live Activity."
    ) async -> ShoppingLiveActivityOperationResult {
        guard beginOperation() else {
            return publishBusyResult()
        }
        defer { isRunningOperation = false }

        guard let activity = currentActivity() else {
            return publish(
                kind: .failed,
                message: "No sample shopping Live Activity is running. Start one before updating it."
            )
        }

        await activity.update(to: state)
        sampleStateVersion = max(sampleStateVersion, state.stateVersion)

        return publish(
            kind: .updated,
            message: successMessage,
            activityID: activity.id
        )
    }

    @discardableResult
    func endSampleActivity() async -> ShoppingLiveActivityOperationResult {
        let timestamp = Self.epochSeconds(from: now())
        return await endSampleActivity(
            with: Self.sampleCompletedState(
                updatedAtEpochSeconds: timestamp,
                stateVersion: sampleStateVersion + 1
            )
        )
    }

    @discardableResult
    func endSampleActivity(
        with finalState: ShoppingTripActivityState
    ) async -> ShoppingLiveActivityOperationResult {
        guard beginOperation() else {
            return publishBusyResult()
        }
        defer { isRunningOperation = false }

        guard let activity = currentActivity() else {
            return publish(
                kind: .failed,
                message: "No sample shopping Live Activity is running. Start one before ending it."
            )
        }

        let endedAt = now()
        await activity.end(
            with: finalState,
            dismissalDate: endedAt.addingTimeInterval(
                Self.completedActivityVisibilityDuration
            )
        )

        activeActivity = nil
        activeActivityID = nil
        nextSampleUpdateIndex = 0
        sampleStateVersion = max(sampleStateVersion, finalState.stateVersion)

        return publish(
            kind: .ended,
            message: "Ended the sample shopping Live Activity. "
                + "Its completed state will remain visible for about 15 minutes.",
            activityID: activity.id
        )
    }

    private func beginOperation() -> Bool {
        guard !isRunningOperation else {
            return false
        }

        isRunningOperation = true
        return true
    }

    private func currentActivity() -> (any ShoppingLiveActivitySession)? {
        if let activeActivity, Self.isDisplayActive(activeActivity) {
            sampleStateVersion = max(sampleStateVersion, activeActivity.stateVersion)
            return activeActivity
        }

        let recoveredActivity = currentSampleActivity()
        activeActivity = recoveredActivity
        activeActivityID = recoveredActivity?.id
        sampleStateVersion = recoveredActivity?.stateVersion ?? 0
        return recoveredActivity
    }

    private func currentSampleActivity() -> (any ShoppingLiveActivitySession)? {
        activityClient.activities.first { activity in
            activity.tripID == Self.sampleTripID && Self.isDisplayActive(activity)
        }
    }

    private static func isDisplayActive(
        _ activity: any ShoppingLiveActivitySession
    ) -> Bool {
        switch activity.activityState {
        case .ended, .dismissed:
            return false
        default:
            return true
        }
    }

    private func publishBusyResult() -> ShoppingLiveActivityOperationResult {
        publish(
            kind: .failed,
            message: "A shopping Live Activity operation is already in progress.",
            activityID: activeActivityID
        )
    }

    private func publish(
        kind: ShoppingLiveActivityOperationKind,
        message: String,
        activityID: String? = nil
    ) -> ShoppingLiveActivityOperationResult {
        let result = ShoppingLiveActivityOperationResult(
            kind: kind,
            message: message,
            activityID: activityID
        )
        statusMessage = message
        lastResult = result
        return result
    }

    private static func nonemptyName(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Levy Home" : trimmedName
    }

    private static func epochSeconds(from date: Date) -> Int {
        Int(date.timeIntervalSince1970)
    }

    private static func sampleInitialState(
        updatedAtEpochSeconds: Int
    ) -> ShoppingTripActivityState {
        ShoppingTripActivityState(
            status: "active",
            pickedUpCount: 3,
            remainingCount: 7,
            totalItemCount: 10,
            estimatedTotalCents: 2_550,
            pricedPickedItemCount: 3,
            unpricedPickedItemCount: 0,
            currencyCode: "USD",
            stateVersion: 1,
            updatedAtEpochSeconds: updatedAtEpochSeconds
        )
    }

    private static func sampleUpdateScenarios(
        updatedAtEpochSeconds: Int,
        stateVersion: Int
    ) -> [(state: ShoppingTripActivityState, description: String)] {
        [
            (
                state: ShoppingTripActivityState(
                    status: "active",
                    pickedUpCount: 0,
                    remainingCount: 0,
                    totalItemCount: 0,
                    estimatedTotalCents: 0,
                    pricedPickedItemCount: 0,
                    unpricedPickedItemCount: 0,
                    currencyCode: "USD",
                    stateVersion: stateVersion,
                    updatedAtEpochSeconds: updatedAtEpochSeconds
                ),
                description: "0 picked up, 0 left, and Est. $0.00"
            ),
            (
                state: ShoppingTripActivityState(
                    status: "active",
                    pickedUpCount: 7,
                    remainingCount: 3,
                    totalItemCount: 10,
                    estimatedTotalCents: 2_550,
                    pricedPickedItemCount: 7,
                    unpricedPickedItemCount: 0,
                    currencyCode: "USD",
                    stateVersion: stateVersion,
                    updatedAtEpochSeconds: updatedAtEpochSeconds
                ),
                description: "7 picked up, 3 left, and Est. $25.50"
            ),
            (
                state: ShoppingTripActivityState(
                    status: "active",
                    pickedUpCount: 1,
                    remainingCount: 99,
                    totalItemCount: 100,
                    estimatedTotalCents: 99_999,
                    pricedPickedItemCount: 1,
                    unpricedPickedItemCount: 0,
                    currencyCode: "USD",
                    stateVersion: stateVersion,
                    updatedAtEpochSeconds: updatedAtEpochSeconds
                ),
                description: "1 picked up, 99 left, and Est. $999.99"
            ),
            (
                state: ShoppingTripActivityState(
                    status: "active",
                    pickedUpCount: 2,
                    remainingCount: 999,
                    totalItemCount: 1_001,
                    estimatedTotalCents: 999_999,
                    pricedPickedItemCount: 1,
                    unpricedPickedItemCount: 1,
                    currencyCode: "USD",
                    stateVersion: stateVersion,
                    updatedAtEpochSeconds: updatedAtEpochSeconds
                ),
                description: "2 picked up, 999 left, and Est. $9,999.99"
            )
        ]
    }

    private static func sampleCompletedState(
        updatedAtEpochSeconds: Int,
        stateVersion: Int
    ) -> ShoppingTripActivityState {
        ShoppingTripActivityState(
            status: "completed",
            pickedUpCount: 8,
            remainingCount: 2,
            totalItemCount: 10,
            estimatedTotalCents: 6_742,
            pricedPickedItemCount: 7,
            unpricedPickedItemCount: 1,
            currencyCode: "USD",
            stateVersion: stateVersion,
            updatedAtEpochSeconds: updatedAtEpochSeconds
        )
    }

    private static let activitiesDisabledMessage =
        "Live Activities are turned off for Levy Home. Enable Live Activities in iOS Settings, then try again."
}
