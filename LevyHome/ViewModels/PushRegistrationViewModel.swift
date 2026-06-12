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

    @Published private(set) var developerStatusMessage: String?
    @Published private(set) var deviceToken: String?
    @Published private(set) var isRegistering = false

    private let service: NotificationServicing

    init(service: NotificationServicing) {
        self.service = service
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

        apply(await service.requestAuthorizationAndRegister(), preserveDeveloperMessage: false)
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
            return
        }

        if snapshot.hasDeviceToken {
            registrationLabel = "Registered"
            registrationDetail = "This device has a native APNs token. Backend sync comes next."
            registrationTone = .success
            registrationSystemImage = "checkmark.circle"
            return
        }

        if snapshot.errorMessage != nil {
            registrationLabel = "Failed"
            registrationDetail = "This device could not finish native push registration."
            registrationTone = .critical
            registrationSystemImage = "exclamationmark.triangle"
            return
        }

        if snapshot.permissionStatus == .denied {
            registrationLabel = "Blocked"
            registrationDetail = "Turn notifications on in iOS Settings before registering this device."
            registrationTone = .warning
            registrationSystemImage = "bell.slash"
            return
        }

        registrationLabel = "Not registered"
        registrationDetail = "Open Developer Tools to request notification permission and APNs registration."
        registrationTone = .neutral
        registrationSystemImage = "iphone"
    }
}
