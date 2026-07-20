import Foundation

enum CameraSessionState: Equatable {
    case placeholder
    case connecting
    case live
    case unavailable(message: String)
}

enum CameraPanTiltDirection: String, CaseIterable, Equatable {
    case up
    case down
    case left
    case right

    var accessibilityLabel: String {
        "Move camera \(rawValue)"
    }
}

enum CameraAudioMenuState: Equatable {
    case hidden
    case visible
}

enum CameraTalkState: Equatable {
    case inactive
    case connecting
    case active
    case unavailable(message: String)
}

protocol CameraSessionServicing {
    func loadSessionState() async throws -> CameraSessionState
    func startSession() async throws -> CameraSessionState
    func stopSession() async throws
}

protocol CameraPanTiltControlling {
    func moveCamera(_ direction: CameraPanTiltDirection) async throws
}

protocol CameraAudioControlling {
    func loadCameraSpeakerVolume() async throws -> Int
    func setCameraSpeakerVolume(_ value: Int) async throws -> Int
    func startTalk() async throws
    func stopTalk() async throws
}
