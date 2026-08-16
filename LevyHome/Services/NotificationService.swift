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
    let registeredDeviceCount: Int?
    let appVersion: String?
    let deviceName: String?
    let syncedAt: Date

    init(
        deviceToken: String,
        environment: APNsEnvironment,
        deviceId: String? = nil,
        registeredDeviceCount: Int?,
        appVersion: String? = nil,
        deviceName: String? = nil,
        syncedAt: Date
    ) {
        self.deviceToken = deviceToken
        self.environment = environment
        self.deviceId = deviceId
        self.registeredDeviceCount = registeredDeviceCount
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.syncedAt = syncedAt
    }

    func matches(
        deviceToken: String,
        environment: APNsEnvironment,
        appVersion: String?,
        deviceName: String?
    ) -> Bool {
        self.deviceToken == deviceToken
            && self.environment == environment
            && self.appVersion == appVersion
            && self.deviceName == deviceName
    }

    func isHeartbeatDue(at date: Date, interval: TimeInterval) -> Bool {
        date.timeIntervalSince(syncedAt) >= interval
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

    private enum TomorrowPreview {
        static let identifierPrefix = "tomorrowPreview."
        static let hour = 22
        static let minute = 0
    }

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

    /// Schedules a short rolling window of local 10 PM previews. Event counts are
    /// intentionally computed on this phone and never leave EventKit.
    func scheduleTomorrowPreviews(
        _ previews: [(eventCount: Int, deliveryDate: Date)],
        calendar: Calendar = .current
    ) async {
        let settings = await notificationCenter.notificationSettings()
        guard PushPermissionStatus(settings.authorizationStatus).allowsNotifications else {
            return
        }

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let existingPreviewIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(TomorrowPreview.identifierPrefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: existingPreviewIdentifiers)

        do {
            for preview in previews {
                let content = UNMutableNotificationContent()
                content.title = "Tomorrow"
                content.body = Self.tomorrowPreviewBody(eventCount: preview.eventCount)
                content.sound = .default
                content.userInfo = [
                    "levyHome": [
                        "destination": "todo",
                        "notificationKind": "tomorrow_preview"
                    ]
                ]

                let components = calendar.dateComponents(
                    [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                    from: preview.deliveryDate
                )
                let request = UNNotificationRequest(
                    identifier: Self.tomorrowPreviewIdentifier(for: preview.deliveryDate),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                try await notificationCenter.add(request)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    static func nextTomorrowPreviewDeliveryDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: TomorrowPreview.hour, minute: TomorrowPreview.minute),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    static func tomorrowPreviewBody(eventCount: Int) -> String {
        let eventDescription = eventCount == 1 ? "1 event" : "\(eventCount) events"
        return "You have \(eventDescription) tomorrow."
    }

    private static func tomorrowPreviewIdentifier(for deliveryDate: Date) -> String {
        "\(TomorrowPreview.identifierPrefix)\(Int(deliveryDate.timeIntervalSince1970))"
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let levyHome = response.notification.request.content.userInfo["levyHome"] as? [String: Any] else {
            return
        }

        switch levyHome["destination"] as? String ?? levyHome["listType"] as? String {
        case "shopping":
            AppNavigationDestination.savePendingDestination("shopping")
            NotificationCenter.default.post(name: .levyHomeOpenShopping, object: nil)
        case "todo":
            AppNavigationDestination.savePendingDestination("todo")
            NotificationCenter.default.post(name: .levyHomeOpenToDo, object: nil)
        default:
            return
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
