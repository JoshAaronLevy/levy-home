import SwiftUI

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

    private let service: CameraService
    private var streamTask: Task<Void, Never>?

    init(service: CameraService) {
        self.service = service
    }

    deinit {
        streamTask?.cancel()
    }

    func start() async {
        guard sessionState != .connecting else { return }

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
        latestFrame = nil
        do {
            try await service.stopSession()
        } catch {
            errorMessage = error.localizedDescription
        }
        if case .unavailable = sessionState {
            return
        }
        sessionState = .placeholder
    }

    func move(_ direction: CameraPanTiltDirection) async {
        guard movingDirection == nil else { return }
        movingDirection = direction
        errorMessage = nil
        defer { movingDirection = nil }

        do {
            try await service.moveCamera(direction)
        } catch {
            errorMessage = error.localizedDescription
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
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let frames = try service.streamFrames()
                for try await frame in frames {
                    guard !Task.isCancelled else { return }
                    latestFrame = frame
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                sessionState = .unavailable(message: error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }
}
