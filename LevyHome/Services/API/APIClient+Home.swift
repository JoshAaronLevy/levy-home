import Foundation

extension APIClient {
    func fetchHomeOverview() async throws -> HomeOverviewResponse {
        try await send(path: "/api/home/overview")
    }

    func fetchQuickActions() async throws -> QuickActionsResponse {
        try await send(path: "/api/home/actions")
    }

    func performQuickAction(_ request: QuickActionRequest) async throws -> QuickActionResponse {
        try await send(path: "/api/home/actions", method: .post, body: request)
    }
}
