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

struct PushAPISyncState: Codable, Equatable {
    let deviceToken: String
    let environment: APNsEnvironment
    let deviceId: String?
    let registeredDeviceCount: Int
    let syncedAt: Date

    init(
        deviceToken: String,
        environment: APNsEnvironment,
        deviceId: String? = nil,
        registeredDeviceCount: Int,
        syncedAt: Date
    ) {
        self.deviceToken = deviceToken
        self.environment = environment
        self.deviceId = deviceId
        self.registeredDeviceCount = registeredDeviceCount
        self.syncedAt = syncedAt
    }

    func matches(deviceToken: String, environment: APNsEnvironment) -> Bool {
        self.deviceToken == deviceToken && self.environment == environment
    }
}

protocol PushRegistrationStateStoring {
    func loadDeviceToken() -> String?
    func saveDeviceToken(_ token: String)
    func loadAPISyncState() -> PushAPISyncState?
    func saveAPISyncState(_ state: PushAPISyncState)
}

final class PushRegistrationStateStore: PushRegistrationStateStoring {
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let deviceTokenKey = "pushRegistration.deviceToken"
    private let apiSyncStateKey = "pushRegistration.apiSyncState"

    init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func loadDeviceToken() -> String? {
        guard let token = userDefaults.string(forKey: deviceTokenKey), !token.isEmpty else {
            return nil
        }

        return token
    }

    func saveDeviceToken(_ token: String) {
        userDefaults.set(token, forKey: deviceTokenKey)
    }

    func loadAPISyncState() -> PushAPISyncState? {
        guard let data = userDefaults.data(forKey: apiSyncStateKey) else {
            return nil
        }

        return try? decoder.decode(PushAPISyncState.self, from: data)
    }

    func saveAPISyncState(_ state: PushAPISyncState) {
        guard let data = try? encoder.encode(state) else {
            return
        }

        userDefaults.set(data, forKey: apiSyncStateKey)
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

final class NotificationService: NSObject, NotificationServicing, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let notificationCenter: UNUserNotificationCenter
    private let stateStore: PushRegistrationStateStoring
    private var deviceToken: String?
    private var lastErrorMessage: String?
    private var registrationContinuation: CheckedContinuation<String, Error>?

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        stateStore: PushRegistrationStateStoring = PushRegistrationStateStore()
    ) {
        self.notificationCenter = notificationCenter
        self.stateStore = stateStore
        self.deviceToken = stateStore.loadDeviceToken()
        super.init()
        self.notificationCenter.delegate = self
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
        stateStore.saveDeviceToken(token)
        lastErrorMessage = nil
        registrationContinuation?.resume(returning: token)
        registrationContinuation = nil
    }

    func handleRegistrationFailure(_ error: Error) {
        lastErrorMessage = error.localizedDescription
        registrationContinuation?.resume(throwing: error)
        registrationContinuation = nil
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
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
