import Foundation

struct CameraStatusResponse: Decodable {
    let ok: Bool
    let camera: CameraStatus
}

struct CameraStatus: Decodable, Equatable {
    let id: String
    let displayName: String
    let isAvailable: Bool
    let isStreaming: Bool
    let speakerVolume: Int
}

struct CameraSessionResponse: Decodable {
    let ok: Bool
    let session: CameraSession
}

struct CameraSession: Decodable, Equatable {
    let id: String
    let streamURL: String
    let expiresAt: String
}

struct CameraPanTiltRequest: Encodable, Equatable {
    let direction: String
}
