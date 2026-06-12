import Foundation
import UIKit
import UserNotifications

enum PushPermissionStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }

    var allowsNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unknown:
            return false
        }
    }
}

enum PushRegistrationAvailability: Equatable {
    case available
    case simulatorUnavailable
}

struct PushRegistrationSnapshot: Equatable {
    let permissionStatus: PushPermissionStatus
    let availability: PushRegistrationAvailability
    let deviceToken: String?
    let errorMessage: String?

    var hasDeviceToken: Bool {
        deviceToken?.isEmpty == false
    }
}

protocol NotificationServicing {
    func currentSnapshot() async -> PushRegistrationSnapshot
    func requestAuthorizationAndRegister() async -> PushRegistrationSnapshot
}

enum NotificationRegistrationError: LocalizedError {
    case registrationAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .registrationAlreadyInProgress:
            return "APNs registration is already in progress."
        }
    }
}

final class NotificationService: NotificationServicing {
    static let shared = NotificationService()

    private let notificationCenter: UNUserNotificationCenter
    private var deviceToken: String?
    private var lastErrorMessage: String?
    private var registrationContinuation: CheckedContinuation<String, Error>?

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func currentSnapshot() async -> PushRegistrationSnapshot {
        let settings = await notificationCenter.notificationSettings()
        return PushRegistrationSnapshot(
            permissionStatus: PushPermissionStatus(settings.authorizationStatus),
            availability: availability,
            deviceToken: deviceToken,
            errorMessage: lastErrorMessage
        )
    }

    func requestAuthorizationAndRegister() async -> PushRegistrationSnapshot {
        guard availability == .available else {
            return PushRegistrationSnapshot(
                permissionStatus: (await currentSnapshot()).permissionStatus,
                availability: availability,
                deviceToken: nil,
                errorMessage: "APNs registration is unavailable in Simulator. Build to a physical iPhone to receive a native token."
            )
        }

        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            let snapshot = await currentSnapshot()

            guard snapshot.permissionStatus.allowsNotifications else {
                lastErrorMessage = nil
                return snapshot
            }

            if snapshot.hasDeviceToken {
                return snapshot
            }

            let token = try await registerForRemoteNotifications()
            deviceToken = token
            lastErrorMessage = nil
            return await currentSnapshot()
        } catch {
            lastErrorMessage = error.localizedDescription
            return PushRegistrationSnapshot(
                permissionStatus: (await currentSnapshot()).permissionStatus,
                availability: availability,
                deviceToken: deviceToken,
                errorMessage: error.localizedDescription
            )
        }
    }

    func handleDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        lastErrorMessage = nil
        registrationContinuation?.resume(returning: token)
        registrationContinuation = nil
    }

    func handleRegistrationFailure(_ error: Error) {
        lastErrorMessage = error.localizedDescription
        registrationContinuation?.resume(throwing: error)
        registrationContinuation = nil
    }

    private var availability: PushRegistrationAvailability {
        #if targetEnvironment(simulator)
        return .simulatorUnavailable
        #else
        return .available
        #endif
    }

    private func registerForRemoteNotifications() async throws -> String {
        guard registrationContinuation == nil else {
            throw NotificationRegistrationError.registrationAlreadyInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            registrationContinuation = continuation
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}
