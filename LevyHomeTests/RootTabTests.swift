import XCTest
@testable import LevyHome

final class RootTabTests: XCTestCase {
    func testTabsUseTheApprovedCameraAndSettingsOrder() {
        XCTAssertEqual(RootTab.allCases, [.home, .list, .todo, .camera, .settings])
    }

    func testCameraAndSettingsUseTheirApprovedLabelsAndSymbols() {
        XCTAssertEqual(RootTab.camera.title, "Camera")
        XCTAssertEqual(RootTab.camera.systemImage, "video")
        XCTAssertEqual(RootTab.settings.title, "Settings")
        XCTAssertEqual(RootTab.settings.systemImage, "gearshape")
    }
}
