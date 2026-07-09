import XCTest
@testable import LevyHome

final class GarageCompletionWatchPolicyTests: XCTestCase {
    func testOpenGarageUsesOpeningThenOpenPolicy() throws {
        let policy = try XCTUnwrap(GarageCompletionWatchPolicy(request: .openGarage))

        XCTAssertEqual(policy.inProgressState, .opening)
        XCTAssertEqual(policy.expectedState, .open)
        XCTAssertEqual(policy.maximumAttempts, 12)
    }

    func testCloseGarageAllowsLongerClosingWindow() throws {
        let policy = try XCTUnwrap(GarageCompletionWatchPolicy(request: .closeGarage))

        XCTAssertEqual(policy.inProgressState, .closing)
        XCTAssertEqual(policy.expectedState, .closed)
        XCTAssertEqual(policy.maximumAttempts, 24)
    }

    func testNonGarageActionsDoNotCreateCompletionWatchPolicy() {
        XCTAssertNil(GarageCompletionWatchPolicy(request: .turnOffAllLights))
        XCTAssertNil(GarageCompletionWatchPolicy(request: .turnOffLightGroup(groupId: "kitchen")))
    }

    func testLightingCompletionPolicyRequiresEveryTargetToReachExpectedState() {
        let policy = LightingCompletionWatchPolicy(turnOn: false)
        let overview = Self.overview(groups: [
            LightGroupStatus(id: "foyer_lights", name: "Foyer", state: .off, lightsOnCount: 0, totalLightCount: 6),
            LightGroupStatus(id: "kitchen_cans", name: "Kitchen Cans", state: .on, lightsOnCount: 4, totalLightCount: 4)
        ])

        XCTAssertTrue(policy.isSatisfied(in: overview, groupIds: ["foyer_lights"]))
        XCTAssertFalse(policy.isSatisfied(in: overview, groupIds: ["foyer_lights", "kitchen_cans"]))
    }

    func testLightingCompletionPolicyWaitsForMissingTargets() {
        let policy = LightingCompletionWatchPolicy(turnOn: true)
        let overview = Self.overview(groups: [
            LightGroupStatus(id: "playroom", name: "Playroom", state: .on, lightsOnCount: 4, totalLightCount: 4)
        ])

        XCTAssertFalse(policy.isSatisfied(in: overview, groupIds: ["playroom", "foyer_lights"]))
        XCTAssertFalse(policy.isSatisfied(in: nil, groupIds: ["playroom"]))
        XCTAssertFalse(policy.isSatisfied(in: overview, groupIds: []))
    }

    private static func overview(groups: [LightGroupStatus]) -> HomeOverview {
        HomeOverview(
            garageStatus: GarageStatus(
                state: .closed,
                displayName: "Main garage",
                lastUpdatedAt: "2026-06-12T14:00:00Z",
                isStale: false
            ),
            lightSummary: LightSummary(
                state: groups.allSatisfy { $0.state == .off } ? .off : .partiallyOn,
                lightsOnCount: nil,
                totalLightCount: nil,
                groups: groups
            ),
            presence: nil,
            recentImportantEvent: nil,
            generatedAt: "2026-06-12T14:00:02Z",
            isPartial: false
        )
    }
}
