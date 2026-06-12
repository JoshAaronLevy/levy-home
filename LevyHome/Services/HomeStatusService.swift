import Foundation

protocol HomeStatusServicing {
    func fetchOverview() async throws -> HomeOverview
}

final class HomeStatusService: HomeStatusServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchOverview() async throws -> HomeOverview {
        try await apiClient.fetchHomeOverview().overview
    }
}
