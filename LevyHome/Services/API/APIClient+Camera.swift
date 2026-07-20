import Foundation

extension APIClient {
    func fetchCameraStatus(cameraAccessToken: String) async throws -> CameraStatusResponse {
        try await send(
            path: "/api/camera/kids-room",
            additionalHeaders: cameraHeaders(cameraAccessToken)
        )
    }

    func startCameraSession(cameraAccessToken: String) async throws -> CameraSessionResponse {
        try await send(
            path: "/api/camera/kids-room/sessions",
            method: .post,
            additionalHeaders: cameraHeaders(cameraAccessToken)
        )
    }

    func stopCameraSession(id: String, cameraAccessToken: String) async throws -> EmptyAPIResponse {
        try await send(
            path: "/api/camera/kids-room/sessions/\(id)",
            method: .delete,
            additionalHeaders: cameraHeaders(cameraAccessToken)
        )
    }

    func moveCamera(_ direction: CameraPanTiltDirection, cameraAccessToken: String) async throws {
        let _: EmptyAPIResponse = try await send(
            path: "/api/camera/kids-room/ptz",
            method: .post,
            body: CameraPanTiltRequest(direction: direction.rawValue.uppercased()),
            additionalHeaders: cameraHeaders(cameraAccessToken)
        )
    }

    func cameraStreamRequest(path: String, cameraAccessToken: String) throws -> URLRequest {
        let url = try makeURL(path: path, queryItems: [])
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(cameraAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }

    private func cameraHeaders(_ cameraAccessToken: String) -> [String: String] {
        ["Authorization": "Bearer \(cameraAccessToken)"]
    }
}
