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
        streamSession: URLSession = .shared,
        appLogStore: APIClientLogging? = nil
    ) {
        self.apiClient = apiClient
        self.cameraAccessToken = cameraAccessToken
        self.streamSession = streamSession

        let tokenIsAvailable = CameraAccessConfigurationDiagnostics.ValueState(cameraAccessToken) == .populated
        appLogStore?.record(
            level: tokenIsAvailable ? .success : .warning,
            category: "Camera",
            title: "Camera service initialized",
            detail: "Camera access: \(tokenIsAvailable ? "available" : "unavailable")."
        )
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
        do {
            _ = try await apiClient.stopCameraSession(id: activeSession.id, cameraAccessToken: try requiredAccessToken())
        } catch APIError.server(statusCode: 404, message: _) {
            // The broker closes a session as soon as its stream connection ends.
            // A second cleanup request is still a successful local stop.
        }
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
        let configuration = streamSession.configuration

        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let queue = OperationQueue()
            queue.name = "com.levyhome.camera.mjpeg"
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 1

            let delegate = MJPEGStreamDelegate(continuation: continuation)
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
            let task = session.dataTask(with: request)
            task.resume()

            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    private func requiredAccessToken() throws -> String {
        guard let cameraAccessToken, !cameraAccessToken.isEmpty, !cameraAccessToken.hasPrefix("$(") else {
            throw CameraServiceError.notConfigured
        }

        return cameraAccessToken
    }
}

private struct MJPEGFrameDecoder {
    private static let maximumFrameSize = 8_000_000

    private var frameData = Data()
    private var isCollectingFrame = false
    private var previousByte: UInt8?

    mutating func append(_ byte: UInt8) -> UIImage? {
        defer { previousByte = byte }

        if previousByte == 0xFF, byte == 0xD8 {
            frameData = Data([0xFF, 0xD8])
            isCollectingFrame = true
            return nil
        }

        guard isCollectingFrame else { return nil }
        frameData.append(byte)

        if previousByte == 0xFF, byte == 0xD9 {
            defer {
                frameData.removeAll(keepingCapacity: true)
                isCollectingFrame = false
            }
            return UIImage(data: frameData)
        }

        if frameData.count > Self.maximumFrameSize {
            frameData.removeAll(keepingCapacity: true)
            isCollectingFrame = false
        }

        return nil
    }
}

private final class MJPEGStreamDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncThrowingStream<UIImage, Error>.Continuation
    private var decoder = MJPEGFrameDecoder()
    private var acceptedResponse = false

    init(continuation: AsyncThrowingStream<UIImage, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
            continuation.finish(throwing: CameraServiceError.streamUnavailable)
            completionHandler(.cancel)
            return
        }

        acceptedResponse = true
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard acceptedResponse else { return }

        for byte in data {
            if let frame = decoder.append(byte) {
                continuation.yield(frame)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error, !error.isTaskCancellation {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }

        session.finishTasksAndInvalidate()
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
