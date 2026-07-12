import Foundation

struct SiriListCommand: Equatable {
    let list: SiriListKind
    let title: String
    let residentName: String
}

protocol SiriListCommandServicing {
    func execute(_ command: SiriListCommand) async -> SiriListCommandResult
}

final class SiriListCommandService: SiriListCommandServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func execute(_ command: SiriListCommand) async -> SiriListCommandResult {
        _ = apiClient
        _ = command

        // Stage 2 establishes the shared boundary only. Stages 3 and 4 add mutations.
        return .notImplemented
    }
}
