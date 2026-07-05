import Foundation

protocol DeviceRegistrationServicing {
    func registerDevice(_ request: RegisterDeviceRequest) async throws -> RegisterDeviceResponse
}

extension APIClient: DeviceRegistrationServicing {}

extension APIClient {
    func fetchNotificationPreferences() async throws -> NotificationPreferencesResponse {
        try await send(path: "/api/notification-preferences")
    }

    func updateNotificationPreferences(
        _ request: NotificationPreferencesUpdateRequest
    ) async throws -> NotificationPreferencesResponse {
        try await send(path: "/api/notification-preferences", method: .put, body: request)
    }

    func registerDevice(_ request: RegisterDeviceRequest) async throws -> RegisterDeviceResponse {
        try await send(path: "/api/devices/register", method: .post, body: request)
    }

    func sendTestPush(_ request: TestPushRequest? = nil) async throws -> TestPushResponse {
        if let request {
            return try await send(path: "/api/debug/send-test-push", method: .post, body: request)
        }

        return try await send(path: "/api/debug/send-test-push", method: .post)
    }

    func sendNotificationPipelineTest() async throws -> TestNotificationPipelineResponse {
        try await send(path: "/api/debug/notification-pipeline-test", method: .post)
    }
}
