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
            pushType: .token,
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
    let shouldStartReplacement: Bool

    init(
        kind: ShoppingLiveActivityOperationKind,
        message: String,
        activityID: String? = nil,
        shouldStartReplacement: Bool = false
    ) {
        self.kind = kind
        self.message = message
        self.activityID = activityID
        self.shouldStartReplacement = shouldStartReplacement
    }

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
    static let automaticRecoveryWindow: TimeInterval = 8 * 60 * 60

    @Published private(set) var activitiesAreEnabled: Bool
    @Published private(set) var activeActivityID: String?
    @Published private(set) var localActivityCount: Int
    @Published private(set) var hasRegisteredPushToStartToken = false
    @Published private(set) var isRunningOperation = false
    @Published private(set) var statusMessage: String
    @Published private(set) var lastResult: ShoppingLiveActivityOperationResult?

    private let activityClient: any ShoppingLiveActivityClient
    private let now: () -> Date
    private var activeActivity: (any ShoppingLiveActivitySession)?
    private var nextSampleUpdateIndex = 0
    private var sampleStateVersion: Int
    private var liveActivityRegistrationService: ShoppingLiveActivityRegistrationServicing?
    private var liveActivityRegistrationContext: LiveActivityRegistrationContext?
    private var pushToStartTokenTask: Task<Void, Never>?
    private var activityUpdatesTask: Task<Void, Never>?
    private var activityTokenTasks: [String: Task<Void, Never>] = [:]

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
        localActivityCount = resolvedActivityClient.activities.count
        sampleStateVersion = recoveredActivity?.stateVersion ?? 0
        statusMessage = recoveredActivity == nil
            ? "No sample shopping Live Activity is running."
            : "Recovered the sample shopping Live Activity."
    }

    var hasActiveActivity: Bool {
        activeActivityID != nil
    }

    func configureRemotePushRegistration(
        service: ShoppingLiveActivityRegistrationServicing,
        pushDeviceId: String?,
        resident: String?,
        environment: APNsEnvironment
    ) {
        liveActivityRegistrationService = service

        guard
            let pushDeviceId,
            let resident = Self.recognizedResidentName(resident)
        else {
            liveActivityRegistrationContext = nil
            return
        }

        liveActivityRegistrationContext = LiveActivityRegistrationContext(
            pushDeviceId: pushDeviceId,
            resident: resident,
            environment: environment
        )
        startRemotePushTokenObservationIfNeeded()
    }

    func refreshState() {
        activitiesAreEnabled = activityClient.activitiesAreEnabled
        activeActivity = currentSampleActivity()
        activeActivityID = activeActivity?.id
        localActivityCount = activityClient.activities.count
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

    @discardableResult
    func startTripActivity(for trip: ShoppingTrip) async -> ShoppingLiveActivityOperationResult {
        guard beginOperation() else {
            return publishBusyResult()
        }
        defer { isRunningOperation = false }

        activitiesAreEnabled = activityClient.activitiesAreEnabled
        let matchingActivities = activeTripActivities(for: trip.id)

        if let existing = matchingActivities.first {
            await retireDuplicateTripActivities(
                Array(matchingActivities.dropFirst()),
                using: trip
            )
            return publish(
                kind: .recovered,
                message: "Recovered this iPhone's shopping Live Activity.",
                activityID: existing.id
            )
        }

        guard activitiesAreEnabled else {
            return publish(
                kind: .unavailable,
                message: "The shopping trip started, but Live Activities are turned off for Levy Home on this iPhone."
            )
        }

        do {
            let activity = try activityClient.requestActivity(
                attributes: ShoppingTripActivityAttributes(
                    tripID: trip.id,
                    startedByName: trip.startedBy,
                    startedAtEpochSeconds: Self.epochSeconds(from: Self.date(from: trip.startedAt) ?? now())
                ),
                initialState: Self.activityState(from: trip, updatedAt: now())
            )
            return publish(
                kind: .started,
                message: "Started this iPhone's shopping Live Activity.",
                activityID: activity.id
            )
        } catch {
            return publish(
                kind: .failed,
                message: "The shopping trip started, but this iPhone could not show its Live Activity: \(error.localizedDescription)"
            )
        }
    }

    @discardableResult
    func recoverTripActivity(for trip: ShoppingTrip) async -> ShoppingLiveActivityOperationResult {
        guard beginOperation() else {
            return publishBusyResult()
        }
        defer { isRunningOperation = false }

        let matchingActivities = activeTripActivities(for: trip.id)
        guard let existing = matchingActivities.first else {
            if activityClient.activities.contains(where: { activity in
                activity.tripID == trip.id && activity.activityState == .dismissed
            }) {
                return publish(
                    kind: .unavailable,
                    message: "This iPhone's shopping Live Activity was dismissed, so Levy Home will not restart it automatically. Start a new shopping trip if you need it again."
                )
            }

            if let startedAt = Self.date(from: trip.startedAt), now().timeIntervalSince(startedAt) >= Self.automaticRecoveryWindow {
                return publish(
                    kind: .unavailable,
                    message: "This shopping trip has been active for over 8 hours, so Levy Home will not restart its Live Activity automatically. End the trip when shopping is finished, or start a new trip."
                )
            }

            return publish(
                kind: .unavailable,
                message: "This iPhone has no local shopping Live Activity to recover.",
                shouldStartReplacement: true
            )
        }

        await retireDuplicateTripActivities(Array(matchingActivities.dropFirst()), using: trip)
        return publish(
            kind: .recovered,
            message: "Recovered this iPhone's shopping Live Activity.",
            activityID: existing.id
        )
    }

    @discardableResult
    func endTripActivity(for trip: ShoppingTrip) async -> ShoppingLiveActivityOperationResult {
        guard beginOperation() else {
            return publishBusyResult()
        }
        defer { isRunningOperation = false }

        let activities = activeTripActivities(for: trip.id)
        guard !activities.isEmpty else {
            return publish(kind: .recovered, message: "No local shopping Live Activity needed ending.")
        }

        let finalState = Self.activityState(from: trip, updatedAt: now())
        for activity in activities {
            await activity.end(
                with: finalState,
                dismissalDate: now().addingTimeInterval(Self.completedActivityVisibilityDuration)
            )
        }
        localActivityCount = activityClient.activities.count
        return publish(kind: .ended, message: "Ended this iPhone's shopping Live Activity.")
    }

    func retireOrphanedTripActivities(keepingTripID tripID: String?) async {
        let orphanedActivities = activityClient.activities.filter { activity in
            Self.isDisplayActive(activity)
                && activity.tripID != Self.sampleTripID
                && activity.tripID != tripID
        }
        guard !orphanedActivities.isEmpty else { return }

        let finalState = ShoppingTripActivityState(
            status: "completed",
            pickedUpCount: 0,
            remainingCount: 0,
            totalItemCount: 0,
            estimatedTotalCents: 0,
            pricedPickedItemCount: 0,
            unpricedPickedItemCount: 0,
            currencyCode: "USD",
            stateVersion: 1,
            updatedAtEpochSeconds: Self.epochSeconds(from: now())
        )
        for activity in orphanedActivities {
            await activity.end(with: finalState, dismissalDate: now())
        }
        localActivityCount = activityClient.activities.count
    }

    @discardableResult
    func updateTripActivity(for trip: ShoppingTrip) async -> ShoppingLiveActivityOperationResult {
        guard beginOperation() else {
            return publishBusyResult()
        }
        defer { isRunningOperation = false }

        let activities = activeTripActivities(for: trip.id)
        guard !activities.isEmpty else {
            return publish(kind: .unavailable, message: "No local shopping Live Activity is running on this iPhone.")
        }

        let state = Self.activityState(from: trip, updatedAt: now())
        for activity in activities where activity.stateVersion < state.stateVersion {
            await activity.update(to: state)
        }
        return publish(
            kind: .updated,
            message: "Updated this iPhone's shopping Live Activity.",
            activityID: activities.first?.id
        )
    }

    private func beginOperation() -> Bool {
        guard !isRunningOperation else {
            return false
        }

        isRunningOperation = true
        return true
    }

    private func startRemotePushTokenObservationIfNeeded() {
        guard liveActivityRegistrationContext != nil else {
            return
        }

        if pushToStartTokenTask == nil {
            pushToStartTokenTask = Task { [weak self] in
                for await token in Activity<ShoppingTripActivityAttributes>.pushToStartTokenUpdates {
                    await self?.registerActivityKitToken(
                        token,
                        tokenType: "push_to_start",
                        tripID: nil
                    )
                }
            }
        }

        if activityUpdatesTask == nil {
            activityUpdatesTask = Task { [weak self] in
                for await activity in Activity<ShoppingTripActivityAttributes>.activityUpdates {
                    self?.observeUpdateTokens(for: activity)
                }
            }
        }

        for activity in Activity<ShoppingTripActivityAttributes>.activities {
            observeUpdateTokens(for: activity)
        }
    }

    private func observeUpdateTokens(for activity: Activity<ShoppingTripActivityAttributes>) {
        guard activityTokenTasks[activity.id] == nil else {
            return
        }

        activityTokenTasks[activity.id] = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                await self?.registerActivityKitToken(
                    token,
                    tokenType: "activity_update",
                    tripID: activity.attributes.tripID
                )
            }
        }
    }

    private func registerActivityKitToken(
        _ token: Data,
        tokenType: String,
        tripID: String?
    ) async {
        guard
            let service = liveActivityRegistrationService,
            let context = liveActivityRegistrationContext
        else {
            return
        }

        let tokenHex = token.map { String(format: "%02x", $0) }.joined()

        do {
            _ = try await service.registerShoppingLiveActivity(
                ShoppingLiveActivityRegistrationRequest(
                    pushDeviceId: context.pushDeviceId,
                    resident: context.resident,
                    environment: context.environment,
                    tokenType: tokenType,
                    token: tokenHex,
                    tripId: tripID
                )
            )
            if tokenType == "push_to_start" {
                hasRegisteredPushToStartToken = true
            }
        } catch {
            // ActivityKit rotates tokens asynchronously. Retaining the prior server token is safer than
            // disturbing an active local activity when the current upload cannot reach the API.
        }
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

    private func activeTripActivities(for tripID: String) -> [any ShoppingLiveActivitySession] {
        activityClient.activities.filter { activity in
            activity.tripID == tripID && Self.isDisplayActive(activity)
        }
    }

    private func retireDuplicateTripActivities(
        _ activities: [any ShoppingLiveActivitySession],
        using trip: ShoppingTrip
    ) async {
        guard !activities.isEmpty else { return }

        // A delayed remote start can race a foreground recovery. Keep the
        // first local display and retire any duplicates without touching the
        // shared backend trip.
        let finalState = Self.activityState(from: trip, updatedAt: now())
        for activity in activities {
            await activity.end(with: finalState, dismissalDate: now())
        }
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
        activityID: String? = nil,
        shouldStartReplacement: Bool = false
    ) -> ShoppingLiveActivityOperationResult {
        let result = ShoppingLiveActivityOperationResult(
            kind: kind,
            message: message,
            activityID: activityID,
            shouldStartReplacement: shouldStartReplacement
        )
        statusMessage = message
        lastResult = result
        return result
    }

    private static func nonemptyName(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Levy Home" : trimmedName
    }

    private static func recognizedResidentName(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed == "Josh" || trimmed == "Mallory") ? trimmed : nil
    }

    private static func epochSeconds(from date: Date) -> Int {
        Int(date.timeIntervalSince1970)
    }

    private static func date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func activityState(from trip: ShoppingTrip, updatedAt: Date) -> ShoppingTripActivityState {
        ShoppingTripActivityState(
            status: trip.status,
            pickedUpCount: trip.pickedUpCount,
            remainingCount: trip.remainingCount,
            totalItemCount: trip.totalItemCount,
            estimatedTotalCents: trip.estimatedTotalCents,
            pricedPickedItemCount: trip.pricedPickedItemCount,
            unpricedPickedItemCount: trip.unpricedPickedItemCount,
            currencyCode: trip.currencyCode,
            stateVersion: trip.version,
            updatedAtEpochSeconds: trip.activityUpdatedAtEpochSeconds
                .flatMap { $0 > 0 ? $0 : nil }
                ?? epochSeconds(from: updatedAt)
        )
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

private struct LiveActivityRegistrationContext {
    let pushDeviceId: String
    let resident: String
    let environment: APNsEnvironment
}
