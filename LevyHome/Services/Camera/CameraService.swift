import Foundation
import UIKit

final class CameraService: CameraSessionServicing, CameraPanTiltControlling, CameraAudioControlling {
    private let apiClient: APIClient
    private let cameraAccessToken: String?
    private let streamSession: URLSession
    private var activeSession: CameraSession?

    init(
        apiClient: APIClient,
        cameraAccessToken: String?,
        streamSession: URLSession = .shared
    ) {
        self.apiClient = apiClient
        self.cameraAccessToken = cameraAccessToken
        self.streamSession = streamSession
    }

    func loadSessionState() async throws -> CameraSessionState {
        let status = try await apiClient.fetchCameraStatus(cameraAccessToken: try requiredAccessToken())
        guard status.camera.isAvailable else {
            return .unavailable(message: "The Kids Room camera is unavailable.")
        }

        return status.camera.isStreaming ? .live : .placeholder
    }

    func startSession() async throws -> CameraSessionState {
        let response = try await apiClient.startCameraSession(cameraAccessToken: try requiredAccessToken())
        activeSession = response.session
        return .live
    }

    func stopSession() async throws {
        guard let activeSession else { return }
        defer { self.activeSession = nil }
        _ = try await apiClient.stopCameraSession(id: activeSession.id, cameraAccessToken: try requiredAccessToken())
    }

    func moveCamera(_ direction: CameraPanTiltDirection) async throws {
        try await apiClient.moveCamera(direction, cameraAccessToken: try requiredAccessToken())
    }

    func loadCameraSpeakerVolume() async throws -> Int {
        try await apiClient.fetchCameraStatus(cameraAccessToken: try requiredAccessToken()).camera.speakerVolume
    }

    func setCameraSpeakerVolume(_ value: Int) async throws -> Int {
        let response = try await apiClient.setCameraSpeakerVolume(value, cameraAccessToken: try requiredAccessToken())
        return response.camera.speakerVolume
    }

    func startTalk() async throws {
        throw CameraServiceError.talkbackUnavailable
    }

    func stopTalk() async throws {}

    func streamFrames() throws -> AsyncThrowingStream<UIImage, Error> {
        guard let activeSession else {
            throw CameraServiceError.noActiveSession
        }

        let request = try apiClient.cameraStreamRequest(path: activeSession.streamURL, cameraAccessToken: requiredAccessToken())
        let session = streamSession

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
                        throw CameraServiceError.streamUnavailable
                    }

                    var frameData = Data()
                    var isCollectingFrame = false
                    var previousByte: UInt8?

                    for try await byte in bytes {
                        if previousByte == 0xFF, byte == 0xD8 {
                            frameData = Data([0xFF, 0xD8])
                            isCollectingFrame = true
                        } else if isCollectingFrame {
                            frameData.append(byte)
                        }

                        if isCollectingFrame, previousByte == 0xFF, byte == 0xD9 {
                            if let image = UIImage(data: frameData) {
                                continuation.yield(image)
                            }
                            frameData.removeAll(keepingCapacity: true)
                            isCollectingFrame = false
                        } else if frameData.count > 8_000_000 {
                            frameData.removeAll(keepingCapacity: true)
                            isCollectingFrame = false
                        }

                        previousByte = byte
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func requiredAccessToken() throws -> String {
        guard let cameraAccessToken, !cameraAccessToken.isEmpty, !cameraAccessToken.hasPrefix("$(") else {
            throw CameraServiceError.notConfigured
        }

        return cameraAccessToken
    }
}

enum CameraServiceError: LocalizedError {
    case noActiveSession
    case notConfigured
    case streamUnavailable
    case talkbackUnavailable

    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            "The camera session has ended."
        case .notConfigured:
            "Camera access has not been configured for this build."
        case .streamUnavailable:
            "The camera stream is unavailable."
        case .talkbackUnavailable:
            "Two-way talk is not configured yet."
        }
    }
}
