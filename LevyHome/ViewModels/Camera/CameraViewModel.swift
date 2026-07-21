import SwiftUI

protocol CameraViewModelServicing: AnyObject {
    func startSession() async throws -> CameraSessionState
    func stopSession() async throws
    func moveCamera(_ direction: CameraPanTiltDirection) async throws
    func loadCameraSpeakerVolume() async throws -> Int
    func setCameraSpeakerVolume(_ value: Int) async throws -> Int
    func streamFrames() throws -> AsyncThrowingStream<UIImage, Error>
}

extension CameraService: CameraViewModelServicing {}

@MainActor
final class CameraViewModel: ObservableObject {
    @Published private(set) var sessionState: CameraSessionState = .placeholder
    @Published private(set) var latestFrame: UIImage?
    @Published private(set) var movingDirection: CameraPanTiltDirection?
    @Published private(set) var errorMessage: String?
    @Published private(set) var audioMenuState: CameraAudioMenuState = .hidden
    @Published private(set) var confirmedSpeakerVolume = 10
    @Published var speakerVolumeDraft = 10
    @Published private(set) var isLoadingSpeakerVolume = false
    @Published private(set) var isSavingSpeakerVolume = false

    private let service: any CameraViewModelServicing
    private let frameInactivityTimeout: TimeInterval
    private let frameWatchdogInterval: Duration
    private let now: () -> Date
    private var streamTask: Task<Void, Never>?
    private var streamWatchdogTask: Task<Void, Never>?
    private var queuedDirection: CameraPanTiltDirection?
    private var lastFrameReceivedAt: Date?
    private var automaticRecoveryAttempts = 0

    init(
        service: any CameraViewModelServicing,
        frameInactivityTimeout: TimeInterval = 12,
        frameWatchdogInterval: Duration = .seconds(2),
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.frameInactivityTimeout = frameInactivityTimeout
        self.frameWatchdogInterval = frameWatchdogInterval
        self.now = now
    }

    deinit {
        streamTask?.cancel()
        streamWatchdogTask?.cancel()
    }

    func start() async {
        guard sessionState == .placeholder || isUnavailable else { return }

        sessionState = .connecting
        errorMessage = nil
        do {
            sessionState = try await service.startSession()
            startFrameStream()
        } catch {
            sessionState = .unavailable(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func retry() async {
        await stop()
        await start()
    }

    func stop() async {
        streamTask?.cancel()
        streamTask = nil
        streamWatchdogTask?.cancel()
        streamWatchdogTask = nil
        queuedDirection = nil
        lastFrameReceivedAt = nil
        automaticRecoveryAttempts = 0
        latestFrame = nil
        do {
            try await service.stopSession()
        } catch {
            errorMessage = error.localizedDescription
        }
        sessionState = .placeholder
    }

    func move(_ direction: CameraPanTiltDirection) async {
        if movingDirection != nil {
            // Keep only the latest requested direction; repeated taps should not
            // disappear while Home Assistant finishes the current movement.
            queuedDirection = direction
            return
        }

        var nextDirection: CameraPanTiltDirection? = direction

        while let currentDirection = nextDirection {
            movingDirection = currentDirection
            errorMessage = nil

            do {
                try await service.moveCamera(currentDirection)
            } catch {
                errorMessage = error.localizedDescription
                queuedDirection = nil
            }

            movingDirection = nil
            nextDirection = queuedDirection
            queuedDirection = nil
        }
    }

    func openSpeakerControls() async {
        audioMenuState = .visible
        isLoadingSpeakerVolume = true
        errorMessage = nil

        do {
            let value = try await service.loadCameraSpeakerVolume()
            confirmedSpeakerVolume = value
            speakerVolumeDraft = value
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingSpeakerVolume = false
    }

    func closeSpeakerControls() {
        speakerVolumeDraft = confirmedSpeakerVolume
        audioMenuState = .hidden
    }

    func applySpeakerVolume() async {
        guard !isSavingSpeakerVolume, speakerVolumeDraft != confirmedSpeakerVolume else { return }

        isSavingSpeakerVolume = true
        errorMessage = nil
        do {
            let confirmedValue = try await service.setCameraSpeakerVolume(speakerVolumeDraft)
            confirmedSpeakerVolume = confirmedValue
            speakerVolumeDraft = confirmedValue
        } catch {
            speakerVolumeDraft = confirmedSpeakerVolume
            errorMessage = "Camera speaker volume was not updated. \(error.localizedDescription)"
        }
        isSavingSpeakerVolume = false
    }

    private func startFrameStream() {
        streamTask?.cancel()
        streamWatchdogTask?.cancel()
        lastFrameReceivedAt = now()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let frames = try service.streamFrames()
                for try await frame in frames {
                    guard !Task.isCancelled else { return }
                    lastFrameReceivedAt = now()
                    latestFrame = frame
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                streamWatchdogTask?.cancel()
                latestFrame = nil
                sessionState = .unavailable(message: error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }

        streamWatchdogTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: frameWatchdogInterval)
                } catch {
                    return
                }

                guard
                    !Task.isCancelled,
                    sessionState == .live,
                    let lastFrameReceivedAt,
                    now().timeIntervalSince(lastFrameReceivedAt) >= frameInactivityTimeout
                else {
                    continue
                }

                await recoverStalledStream()
                return
            }
        }
    }

    private func recoverStalledStream() async {
        streamTask?.cancel()
        streamTask = nil
        latestFrame = nil
        lastFrameReceivedAt = nil

        guard automaticRecoveryAttempts == 0 else {
            let message = "Live video stopped updating. Try Again."
            sessionState = .unavailable(message: message)
            errorMessage = message
            return
        }

        automaticRecoveryAttempts += 1
        sessionState = .connecting
        errorMessage = nil

        do {
            try await service.stopSession()
            sessionState = try await service.startSession()
            startFrameStream()
        } catch {
            sessionState = .unavailable(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = sessionState {
            return true
        }
        return false
    }
}
