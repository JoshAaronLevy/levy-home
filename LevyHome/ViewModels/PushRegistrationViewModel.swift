import Foundation

@MainActor
final class PushRegistrationViewModel: ObservableObject {
    @Published private(set) var permissionLabel = "Checking"
    @Published private(set) var permissionDetail = "Checking iOS notification settings."
    @Published private(set) var permissionTone: StatusBadgeTone = .neutral
    @Published private(set) var permissionSystemImage = "clock"

    @Published private(set) var registrationLabel = "Checking"
    @Published private(set) var registrationDetail = "Checking push registration on this device."
    @Published private(set) var registrationTone: StatusBadgeTone = .neutral
    @Published private(set) var registrationSystemImage = "clock"

    @Published private(set) var apiRegistrationLabel = "Not synced"
    @Published private(set) var apiRegistrationDetail = "API device registration waits for a native APNs token."
    @Published private(set) var apiRegistrationTone: StatusBadgeTone = .neutral
    @Published private(set) var apiRegistrationSystemImage = "arrow.triangle.2.circlepath"

    @Published private(set) var developerStatusMessage: String?
    @Published private(set) var deviceToken: String?
    @Published private(set) var isRegistering = false

    private let service: NotificationServicing
    private let deviceRegistrationService: DeviceRegistrationServicing?
    private let apnsEnvironment: APNsEnvironment
    private let appVersion: String?
    private let deviceName: String?

    init(
        service: NotificationServicing,
        deviceRegistrationService: DeviceRegistrationServicing? = nil,
        apnsEnvironment: APNsEnvironment = .sandbox,
        appVersion: String? = nil,
        deviceName: String? = nil
    ) {
        self.service = service
        self.deviceRegistrationService = deviceRegistrationService
        self.apnsEnvironment = apnsEnvironment
        self.appVersion = appVersion
        self.deviceName = deviceName
    }

    func refreshStatus() async {
        guard !isRegistering else {
            return
        }

        apply(await service.currentSnapshot(), preserveDeveloperMessage: true)
    }

    func requestRegistration() async {
        guard !isRegistering else {
            return
        }

        isRegistering = true
        developerStatusMessage = nil
        defer {
            isRegistering = false
        }

        let snapshot = await service.requestAuthorizationAndRegister()
        apply(snapshot, preserveDeveloperMessage: false)

        await syncDeviceWithAPIIfPossible(snapshot)
    }

    private func apply(
        _ snapshot: PushRegistrationSnapshot,
        preserveDeveloperMessage: Bool
    ) {
        deviceToken = snapshot.deviceToken
        applyPermission(snapshot.permissionStatus)
        applyRegistration(snapshot)

        guard !preserveDeveloperMessage else {
            return
        }

        if let errorMessage = snapshot.errorMessage {
            developerStatusMessage = errorMessage
        } else if snapshot.availability == .simulatorUnavailable {
            developerStatusMessage = "Simulator cannot receive a native APNs device token."
        } else if snapshot.hasDeviceToken {
            developerStatusMessage = "Native APNs token is available on this device."
        } else if snapshot.permissionStatus == .denied {
            developerStatusMessage = "Notification permission is denied in iOS Settings."
        } else {
            developerStatusMessage = "Notification registration is pending."
        }
    }

    private func applyPermission(_ status: PushPermissionStatus) {
        switch status {
        case .authorized:
            permissionLabel = "Allowed"
            permissionDetail = "iOS allows Levy Home notifications on this device."
            permissionTone = .success
            permissionSystemImage = "bell"
        case .provisional, .ephemeral:
            permissionLabel = "Allowed"
            permissionDetail = "iOS allows Levy Home notifications with limited delivery."
            permissionTone = .success
            permissionSystemImage = "bell"
        case .denied:
            permissionLabel = "Off"
            permissionDetail = "iOS notifications are turned off for Levy Home."
            permissionTone = .warning
            permissionSystemImage = "bell.slash"
        case .notDetermined:
            permissionLabel = "Not requested"
            permissionDetail = "Levy Home has not asked for notification permission yet."
            permissionTone = .neutral
            permissionSystemImage = "bell.badge"
        case .unknown:
            permissionLabel = "Unknown"
            permissionDetail = "Levy Home could not read the current notification setting."
            permissionTone = .neutral
            permissionSystemImage = "questionmark.circle"
        }
    }

    private func applyRegistration(_ snapshot: PushRegistrationSnapshot) {
        if snapshot.availability == .simulatorUnavailable {
            registrationLabel = "Unavailable"
            registrationDetail = "Native APNs tokens are only available on a physical iPhone."
            registrationTone = .neutral
            registrationSystemImage = "iphone.slash"
            applyAPISyncSkipped("Backend sync waits for a physical-device APNs token.")
            return
        }

        if snapshot.hasDeviceToken {
            registrationLabel = "Registered"
            registrationDetail = "This device has a native APNs token. Backend sync comes next."
            registrationTone = .success
            registrationSystemImage = "checkmark.circle"
            applyAPISyncPending()
            return
        }

        if snapshot.errorMessage != nil {
            registrationLabel = "Failed"
            registrationDetail = "This device could not finish native push registration."
            registrationTone = .critical
            registrationSystemImage = "exclamationmark.triangle"
            applyAPISyncSkipped("Backend sync waits for native push registration to recover.")
            return
        }

        if snapshot.permissionStatus == .denied {
            registrationLabel = "Blocked"
            registrationDetail = "Turn notifications on in iOS Settings before registering this device."
            registrationTone = .warning
            registrationSystemImage = "bell.slash"
            applyAPISyncSkipped("Backend sync waits for notification permission.")
            return
        }

        registrationLabel = "Not registered"
        registrationDetail = "Open the Developer screen to request notification permission and APNs registration."
        registrationTone = .neutral
        registrationSystemImage = "iphone"
        applyAPISyncPending()
    }

    private func syncDeviceWithAPIIfPossible(_ snapshot: PushRegistrationSnapshot) async {
        guard snapshot.availability == .available else {
            applyAPISyncSkipped("Backend sync waits for a physical-device APNs token.")
            return
        }

        guard let token = snapshot.deviceToken, !token.isEmpty else {
            applyAPISyncSkipped("Backend sync waits for native push registration.")
            return
        }

        guard let deviceRegistrationService else {
            applyAPISyncSkipped("API device registration is not configured yet.")
            return
        }

        applyAPISyncInProgress()

        do {
            let response = try await deviceRegistrationService.registerDevice(
                RegisterDeviceRequest(
                    token: token,
                    platform: .iOS,
                    provider: .apns,
                    environment: apnsEnvironment,
                    appVersion: appVersion,
                    deviceName: deviceName
                )
            )

            apiRegistrationLabel = "Synced"
            apiRegistrationDetail = "This device is registered with the Levy Home API."
            apiRegistrationTone = .success
            apiRegistrationSystemImage = "checkmark.circle"
            developerStatusMessage = "API device registration succeeded. Registered devices: \(response.registeredDeviceCount)."
        } catch {
            apiRegistrationLabel = "Failed"
            apiRegistrationDetail = "The API could not sync this device. Notifications may not arrive yet."
            apiRegistrationTone = .warning
            apiRegistrationSystemImage = "exclamationmark.triangle"
            developerStatusMessage = "API device registration failed: \(error.localizedDescription)"
        }
    }

    private func applyAPISyncPending() {
        apiRegistrationLabel = "Not synced"
        apiRegistrationDetail = "API device registration has not run yet."
        apiRegistrationTone = .neutral
        apiRegistrationSystemImage = "arrow.triangle.2.circlepath"
    }

    private func applyAPISyncInProgress() {
        apiRegistrationLabel = "Syncing"
        apiRegistrationDetail = "Registering this APNs device token with the Levy Home API."
        apiRegistrationTone = .accent
        apiRegistrationSystemImage = "arrow.triangle.2.circlepath"
    }

    private func applyAPISyncSkipped(_ detail: String) {
        apiRegistrationLabel = "Skipped"
        apiRegistrationDetail = detail
        apiRegistrationTone = .neutral
        apiRegistrationSystemImage = "forward"
    }
}
