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
}
