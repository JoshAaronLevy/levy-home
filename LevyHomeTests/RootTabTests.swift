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

    func testCameraDiagnosticsClassifyValuesWithoutRetainingSecrets() {
        let diagnostics = CameraAccessConfigurationDiagnostics(
            processEnvironmentValue: "   ",
            bundleInfoValue: "$(LEVY_HOME_CAMERA_ACCESS_TOKEN)",
            resolvedToken: "private-test-token"
        )

        XCTAssertEqual(diagnostics.processEnvironment, .empty)
        XCTAssertEqual(diagnostics.bundleInfo, .unresolved)
        XCTAssertTrue(diagnostics.resolvedTokenIsAvailable)
        XCTAssertFalse(diagnostics.logDetail.contains("private-test-token"))
    }

    func testCameraDiagnosticsReportMissingResolvedToken() {
        let diagnostics = CameraAccessConfigurationDiagnostics(
            processEnvironmentValue: nil,
            bundleInfoValue: "",
            resolvedToken: nil
        )

        XCTAssertEqual(diagnostics.processEnvironment, .absent)
        XCTAssertEqual(diagnostics.bundleInfo, .empty)
        XCTAssertFalse(diagnostics.resolvedTokenIsAvailable)
    }
}

@MainActor
final class CameraStreamLivenessTests: XCTestCase {
    func testStalledFramesRestartOnceThenShowUnavailableInsteadOfFrozenImage() async throws {
        let service = StallingCameraService()
        let viewModel = CameraViewModel(
            service: service,
            frameInactivityTimeout: 0.02,
            frameWatchdogInterval: .milliseconds(5)
        )

        await viewModel.start()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(service.startSessionCallCount, 2)
        XCTAssertEqual(service.stopSessionCallCount, 1)
        XCTAssertNil(viewModel.latestFrame)
        XCTAssertEqual(
            viewModel.sessionState,
            .unavailable(message: "Live video stopped updating. Try Again.")
        )
    }
}

private final class StallingCameraService: CameraViewModelServicing {
    private(set) var startSessionCallCount = 0
    private(set) var stopSessionCallCount = 0

    func startSession() async throws -> CameraSessionState {
        startSessionCallCount += 1
        return .live
    }

    func stopSession() async throws {
        stopSessionCallCount += 1
    }

    func moveCamera(_ direction: CameraPanTiltDirection) async throws {}

    func loadCameraSpeakerVolume() async throws -> Int { 10 }

    func setCameraSpeakerVolume(_ value: Int) async throws -> Int { value }

    func streamFrames() throws -> AsyncThrowingStream<UIImage, Error> {
        AsyncThrowingStream { _ in }
    }
}
