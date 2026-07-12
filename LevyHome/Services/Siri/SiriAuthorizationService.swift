import Combine
import Intents

@MainActor
final class SiriAuthorizationService: ObservableObject {
    @Published private(set) var status: INSiriAuthorizationStatus

    init(status: INSiriAuthorizationStatus = INPreferences.siriAuthorizationStatus()) {
        self.status = status
    }

    func refresh() {
        status = INPreferences.siriAuthorizationStatus()
    }

    func requestAuthorization() {
        guard status == .notDetermined else {
            return
        }

        INPreferences.requestSiriAuthorization { [weak self] status in
            Task { @MainActor in
                self?.status = status
            }
        }
    }
}
