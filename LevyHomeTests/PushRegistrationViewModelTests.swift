import XCTest
@testable import LevyHome

@MainActor
final class PushRegistrationViewModelTests: XCTestCase {
    func testRefreshShowsSimulatorUnavailableState() async {
        let viewModel = PushRegistrationViewModel(
            service: MockNotificationService(
                currentSnapshot: PushRegistrationSnapshot(
                    permissionStatus: .notDetermined,
                    availability: .simulatorUnavailable,
                    deviceToken: nil,
                    errorMessage: nil
                )
            )
        )

        await viewModel.refreshStatus()

        XCTAssertEqual(viewModel.permissionLabel, "Not requested")
        XCTAssertEqual(viewModel.registrationLabel, "Unavailable")
        XCTAssertEqual(viewModel.registrationTone, .neutral)
        XCTAssertNil(viewModel.deviceToken)
    }

    func testRegistrationSuccessShowsNativeTokenState() async {
        let viewModel = PushRegistrationViewModel(
            service: MockNotificationService(
                registrationSnapshot: PushRegistrationSnapshot(
                    permissionStatus: .authorized,
                    availability: .available,
                    deviceToken: "abc123",
                    errorMessage: nil
                )
            )
        )

        await viewModel.requestRegistration()

        XCTAssertEqual(viewModel.permissionLabel, "Allowed")
        XCTAssertEqual(viewModel.registrationLabel, "Registered")
        XCTAssertEqual(viewModel.registrationTone, .success)
        XCTAssertEqual(viewModel.deviceToken, "abc123")
        XCTAssertEqual(viewModel.developerStatusMessage, "Native APNs token is available on this device.")
    }

    func testPermissionDeniedShowsBlockedState() async {
        let viewModel = PushRegistrationViewModel(
            service: MockNotificationService(
                registrationSnapshot: PushRegistrationSnapshot(
                    permissionStatus: .denied,
                    availability: .available,
                    deviceToken: nil,
                    errorMessage: nil
                )
            )
        )

        await viewModel.requestRegistration()

        XCTAssertEqual(viewModel.permissionLabel, "Off")
        XCTAssertEqual(viewModel.registrationLabel, "Blocked")
        XCTAssertEqual(viewModel.registrationTone, .warning)
        XCTAssertEqual(viewModel.developerStatusMessage, "Notification permission is denied in iOS Settings.")
    }

    func testRegistrationFailureShowsFailureState() async {
        let viewModel = PushRegistrationViewModel(
            service: MockNotificationService(
                registrationSnapshot: PushRegistrationSnapshot(
                    permissionStatus: .authorized,
                    availability: .available,
                    deviceToken: nil,
                    errorMessage: "Missing entitlement."
                )
            )
        )

        await viewModel.requestRegistration()

        XCTAssertEqual(viewModel.permissionLabel, "Allowed")
        XCTAssertEqual(viewModel.registrationLabel, "Failed")
        XCTAssertEqual(viewModel.registrationTone, .critical)
        XCTAssertEqual(viewModel.developerStatusMessage, "Missing entitlement.")
    }

    func testDuplicateRegistrationRequestsAreIgnoredWhileInProgress() async {
        let service = MockNotificationService(
            registrationSnapshot: PushRegistrationSnapshot(
                permissionStatus: .authorized,
                availability: .available,
                deviceToken: "abc123",
                errorMessage: nil
            ),
            delayNanoseconds: 100_000_000
        )
        let viewModel = PushRegistrationViewModel(service: service)

        async let first: Void = viewModel.requestRegistration()
        async let second: Void = viewModel.requestRegistration()

        _ = await (first, second)

        XCTAssertEqual(service.registrationRequestCount, 1)
        XCTAssertEqual(viewModel.registrationLabel, "Registered")
    }
}

private final class MockNotificationService: NotificationServicing {
    private let currentSnapshotValue: PushRegistrationSnapshot
    private let registrationSnapshotValue: PushRegistrationSnapshot
    private let delayNanoseconds: UInt64
    private(set) var registrationRequestCount = 0

    init(
        currentSnapshot: PushRegistrationSnapshot = PushRegistrationSnapshot(
            permissionStatus: .notDetermined,
            availability: .available,
            deviceToken: nil,
            errorMessage: nil
        ),
        registrationSnapshot: PushRegistrationSnapshot = PushRegistrationSnapshot(
            permissionStatus: .authorized,
            availability: .available,
            deviceToken: "abc123",
            errorMessage: nil
        ),
        delayNanoseconds: UInt64 = 0
    ) {
        self.currentSnapshotValue = currentSnapshot
        self.registrationSnapshotValue = registrationSnapshot
        self.delayNanoseconds = delayNanoseconds
    }

    func currentSnapshot() async -> PushRegistrationSnapshot {
        currentSnapshotValue
    }

    func requestAuthorizationAndRegister() async -> PushRegistrationSnapshot {
        registrationRequestCount += 1

        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        return registrationSnapshotValue
    }
}
