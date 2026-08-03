import AVFAudio
import Foundation
import Speech

enum ShoppingSpeechTranscriptComposer {
    static func combine(existingText: String, transcript: String) -> String {
        let existing = existingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !existing.isEmpty else {
            return spoken
        }
        guard !spoken.isEmpty else {
            return existing
        }

        return "\(existing) \(spoken)"
    }
}

@MainActor
enum ShoppingSpeechTranscriptionState: Equatable {
    case idle
    case requestingPermission
    case listening
    case unavailable(String)
    case denied
    case interrupted
    case failed(String)

    var isListening: Bool {
        if case .listening = self {
            return true
        }

        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .requestingPermission:
            return "Requesting microphone and speech access…"
        case .listening:
            return "Listening… Tap Stop when you are finished."
        case .unavailable(let message), .failed(let message):
            return message
        case .denied:
            return "Microphone or speech recognition access is not allowed. You can still type your request."
        case .interrupted:
            return "Voice input was interrupted. You can keep editing the text or try again."
        }
    }
}

@MainActor
enum ShoppingSpeechAuthorization: Equatable {
    case authorized
    case denied
    case restricted
    case unavailable
}

enum ShoppingSpeechRuntimeError: LocalizedError, Equatable {
    case interrupted
    case unavailable

    var errorDescription: String? {
        switch self {
        case .interrupted:
            return "Voice input was interrupted."
        case .unavailable:
            return "Speech recognition is unavailable for the selected language."
        }
    }
}

/// The runtime boundary keeps audio and partial transcripts on-device until the
/// Shopping sheet explicitly submits its text through the normal API path.
@MainActor
protocol ShoppingSpeechRecognitionRuntime: AnyObject {
    var isRecognitionAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }

    func selectLanguage(locale: Locale)
    func requestSpeechAuthorization() async -> ShoppingSpeechAuthorization
    func requestMicrophonePermission() async -> Bool
    func startRecognition(
        onPartialTranscript: @escaping (String) -> Void,
        onCompletion: @escaping (Result<Void, Error>) -> Void
    ) throws
    func finishRecognition()
    func cancelRecognition()
}

@MainActor
final class ShoppingSpeechTranscriptionService: ObservableObject {
    @Published private(set) var state: ShoppingSpeechTranscriptionState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var selectedLanguageIdentifier: String

    private let runtime: ShoppingSpeechRecognitionRuntime

    init(
        locale: Locale = .current,
        runtime: ShoppingSpeechRecognitionRuntime? = nil
    ) {
        selectedLanguageIdentifier = locale.identifier
        self.runtime = runtime ?? AppleShoppingSpeechRecognitionRuntime(locale: locale)
    }

    var isListening: Bool {
        state.isListening
    }

    var isCapturing: Bool {
        switch state {
        case .requestingPermission, .listening:
            return true
        case .idle, .unavailable, .denied, .interrupted, .failed:
            return false
        }
    }

    var usesOnDeviceRecognitionWhenAvailable: Bool {
        runtime.supportsOnDeviceRecognition
    }

    func selectLanguage(identifier: String) {
        guard !isListening else {
            return
        }

        let locale = Locale(identifier: identifier)
        selectedLanguageIdentifier = identifier
        runtime.selectLanguage(locale: locale)
        transcript = ""
        state = .idle
    }

    func startTranscribing() async {
        guard !isListening else {
            return
        }

        transcript = ""
        state = .requestingPermission

        let speechAuthorization = await runtime.requestSpeechAuthorization()
        guard speechAuthorization == .authorized else {
            state = .denied
            return
        }

        guard await runtime.requestMicrophonePermission() else {
            state = .denied
            return
        }

        guard runtime.isRecognitionAvailable else {
            state = .unavailable("Speech recognition is unavailable for the selected language. You can still type your request.")
            return
        }

        do {
            try runtime.startRecognition(
                onPartialTranscript: { [weak self] transcript in
                    self?.transcript = transcript
                },
                onCompletion: { [weak self] result in
                    self?.handleRecognitionCompletion(result)
                }
            )
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopTranscribing() {
        guard isListening else {
            return
        }

        runtime.finishRecognition()
        state = .idle
    }

    func cancelTranscribing() {
        guard isListening || state == .requestingPermission else {
            return
        }

        runtime.cancelRecognition()
        transcript = ""
        state = .idle
    }

    private func handleRecognitionCompletion(_ result: Result<Void, Error>) {
        guard isListening else {
            return
        }

        switch result {
        case .success:
            state = .idle
        case .failure(let error):
            if error as? ShoppingSpeechRuntimeError == .interrupted {
                state = .interrupted
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

@MainActor
private final class AppleShoppingSpeechRecognitionRuntime: NSObject, ShoppingSpeechRecognitionRuntime {
    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var interruptionObserver: NSObjectProtocol?

    init(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
        super.init()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .began else {
                return
            }

            Task { @MainActor [weak self] in
                self?.completeWithInterruption()
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    var isRecognitionAvailable: Bool {
        recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true
    }

    var supportsOnDeviceRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    func selectLanguage(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func requestSpeechAuthorization() async -> ShoppingSpeechAuthorization {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    switch status {
                    case .authorized:
                        continuation.resume(returning: .authorized)
                    case .denied:
                        continuation.resume(returning: .denied)
                    case .restricted:
                        continuation.resume(returning: .restricted)
                    case .notDetermined:
                        continuation.resume(returning: .unavailable)
                    @unknown default:
                        continuation.resume(returning: .unavailable)
                    }
                }
            }
        @unknown default:
            return .unavailable
        }
    }

    func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func startRecognition(
        onPartialTranscript: @escaping (String) -> Void,
        onCompletion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw ShoppingSpeechRuntimeError.unavailable
        }

        tearDownRecognition(cancelTask: true)
        completion = onCompletion

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // This dedicated control is intentionally local-only. If a selected
        // language cannot be recognized on-device, the UI falls back to typing.
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onPartialTranscript(result.bestTranscription.formattedString)
                if result.isFinal {
                    self?.completeRecognition(.success(()))
                }
                return
            }

            if let error {
                self?.completeRecognition(.failure(error))
            }
        }
    }

    func finishRecognition() {
        tearDownRecognition(cancelTask: false)
    }

    func cancelRecognition() {
        tearDownRecognition(cancelTask: true)
    }

    private func completeWithInterruption() {
        completeRecognition(.failure(ShoppingSpeechRuntimeError.interrupted))
    }

    private func completeRecognition(_ result: Result<Void, Error>) {
        let completion = completion
        tearDownRecognition(cancelTask: true)
        completion?(result)
    }

    private func tearDownRecognition(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionRequest = nil
        recognitionTask = nil
        completion = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
