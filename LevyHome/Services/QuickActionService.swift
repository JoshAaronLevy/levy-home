import Foundation

struct QuickActionCatalog: Equatable {
    let actions: [QuickAction]
    let lightGroups: [LightActionGroup]
}

protocol QuickActionServicing {
    func fetchCatalog() async throws -> QuickActionCatalog
    func perform(_ request: QuickActionRequest) async throws -> QuickActionResult
}

final class QuickActionService: QuickActionServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchCatalog() async throws -> QuickActionCatalog {
        let response = try await apiClient.fetchQuickActions()
        return QuickActionCatalog(
            actions: response.actions,
            lightGroups: response.lightGroups ?? []
        )
    }

    func perform(_ request: QuickActionRequest) async throws -> QuickActionResult {
        try await apiClient.performQuickAction(request).result
    }
}
