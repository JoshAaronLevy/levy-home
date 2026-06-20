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
    private let appLogStore: AppLogStore?

    init(apiClient: APIClient, appLogStore: AppLogStore? = nil) {
        self.apiClient = apiClient
        self.appLogStore = appLogStore
    }

    func fetchCatalog() async throws -> QuickActionCatalog {
        let response = try await apiClient.fetchQuickActions()
        return QuickActionCatalog(
            actions: response.actions,
            lightGroups: response.lightGroups ?? []
        )
    }

    func perform(_ request: QuickActionRequest) async throws -> QuickActionResult {
        appLogStore?.record(
            level: .info,
            category: "Action",
            title: "\(request.logTitle) requested",
            detail: "Submitting \(request.actionId.rawValue) to the Levy Home API."
        )

        do {
            let result = try await apiClient.performQuickAction(request).result
            appLogStore?.record(
                level: result.logLevel,
                category: "Action",
                title: "\(request.logTitle) \(result.logOutcome)",
                detail: result.message
            )
            return result
        } catch {
            appLogStore?.record(
                level: .error,
                category: "Action",
                title: "\(request.logTitle) failed",
                detail: error.localizedDescription
            )
            throw error
        }
    }
}

private extension QuickActionRequest {
    var logTitle: String {
        switch self {
        case .openGarage:
            return "Open Garage"
        case .closeGarage:
            return "Close Garage"
        case .turnOffAllLights:
            return "Turn Off All Lights"
        case .turnOffLightGroup:
            return "Turn Off Light Group"
        }
    }
}

private extension QuickActionResult {
    var logLevel: AppLogLevel {
        switch status {
        case .success:
            return .success
        case .failure:
            return .error
        case .unknown:
            return .warning
        }
    }

    var logOutcome: String {
        switch status {
        case .success:
            return "succeeded"
        case .failure:
            return "failed"
        case .unknown:
            return "finished"
        }
    }
}
