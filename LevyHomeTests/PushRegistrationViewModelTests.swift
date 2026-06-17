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
        XCTAssertEqual(viewModel.apiRegistrationLabel, "Skipped")
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
        XCTAssertEqual(viewModel.apiRegistrationLabel, "Skipped")
        XCTAssertEqual(viewModel.developerStatusMessage, "Native APNs token is available on this device.")
    }

    func testRegistrationSuccessSyncsDeviceWithAPI() async {
        let apiService = MockDeviceRegistrationService(
            response: RegisterDeviceResponse(
                ok: true,
                registeredDeviceCount: 2,
                device: RegisteredDevice(
                    id: "device-1",
                    platform: .iOS,
                    provider: .apns,
                    environment: .sandbox,
                    registeredAt: nil,
                    lastSeenAt: nil
                )
            )
        )
        let viewModel = PushRegistrationViewModel(
            service: MockNotificationService(
                registrationSnapshot: PushRegistrationSnapshot(
                    permissionStatus: .authorized,
                    availability: .available,
                    deviceToken: "abc123",
                    errorMessage: nil
                )
            ),
            deviceRegistrationService: apiService,
            apnsEnvironment: .sandbox,
            appVersion: "0.1.0",
            deviceName: "Joshs iPhone"
        )

        await viewModel.requestRegistration()

        XCTAssertEqual(viewModel.registrationLabel, "Registered")
        XCTAssertEqual(viewModel.apiRegistrationLabel, "Synced")
        XCTAssertEqual(viewModel.apiRegistrationTone, .success)
        XCTAssertEqual(viewModel.developerStatusMessage, "API device registration succeeded. Registered devices: 2.")
        XCTAssertEqual(apiService.requests, [
            RegisterDeviceRequest(
                token: "abc123",
                platform: .iOS,
                provider: .apns,
                environment: .sandbox,
                appVersion: "0.1.0",
                deviceName: "Joshs iPhone"
            )
        ])
    }

    func testRegistrationAPIFailureKeepsNativeTokenAndShowsTechnicalFailure() async {
        let apiService = MockDeviceRegistrationService(error: APIError.server(statusCode: 503, message: "Devices unavailable."))
        let viewModel = PushRegistrationViewModel(
            service: MockNotificationService(
                registrationSnapshot: PushRegistrationSnapshot(
                    permissionStatus: .authorized,
                    availability: .available,
                    deviceToken: "abc123",
                    errorMessage: nil
                )
            ),
            deviceRegistrationService: apiService,
            apnsEnvironment: .sandbox
        )

        await viewModel.requestRegistration()

        XCTAssertEqual(viewModel.registrationLabel, "Registered")
        XCTAssertEqual(viewModel.deviceToken, "abc123")
        XCTAssertEqual(viewModel.apiRegistrationLabel, "Failed")
        XCTAssertEqual(viewModel.apiRegistrationTone, .warning)
        XCTAssertEqual(viewModel.developerStatusMessage, "API device registration failed: Devices unavailable.")
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

private final class MockDeviceRegistrationService: DeviceRegistrationServicing {
    private let response: RegisterDeviceResponse?
    private let error: Error?
    private(set) var requests: [RegisterDeviceRequest] = []

    init(
        response: RegisterDeviceResponse? = nil,
        error: Error? = nil
    ) {
        self.response = response
        self.error = error
    }

    func registerDevice(_ request: RegisterDeviceRequest) async throws -> RegisterDeviceResponse {
        requests.append(request)

        if let error {
            throw error
        }

        return response ?? RegisterDeviceResponse(ok: true, registeredDeviceCount: 1, device: nil)
    }
}
