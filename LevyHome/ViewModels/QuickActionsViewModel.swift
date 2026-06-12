import Combine
import Foundation

struct QuickActionDisplayData: Identifiable, Equatable {
    let id: String
    let request: QuickActionRequest
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let requiresConfirmation: Bool
}

struct QuickActionMessage: Equatable {
    let text: String
    let tone: BannerTone
}

@MainActor
final class QuickActionsViewModel: ObservableObject {
    @Published private(set) var actions: [QuickActionDisplayData] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPerforming = false
    @Published private(set) var performingActionID: String?
    @Published private(set) var message: QuickActionMessage?
    @Published private(set) var pendingConfirmationAction: QuickActionDisplayData?

    private let service: QuickActionServicing
    private var hasLoaded = false

    var isBusy: Bool {
        isLoading || isPerforming
    }

    var subtitle: String {
        if isLoading {
            return "Loading configured actions"
        }

        if actions.isEmpty {
            return "No configured quick actions"
        }

        return "Curated Home Assistant actions"
    }

    init(service: QuickActionServicing) {
        self.service = service
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await load()
    }

    func refresh() async {
        await load()
    }

    func select(_ action: QuickActionDisplayData) async -> HomeOverview? {
        guard action.isEnabled, !isBusy else {
            return nil
        }

        if action.requiresConfirmation {
            pendingConfirmationAction = action
            return nil
        }

        return await perform(action)
    }

    func confirmPendingAction() async -> HomeOverview? {
        guard let action = pendingConfirmationAction else {
            return nil
        }

        pendingConfirmationAction = nil
        return await perform(action)
    }

    func cancelPendingConfirmation() {
        pendingConfirmationAction = nil
    }

    private func load() async {
        guard !isLoading, !isPerforming else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let catalog = try await service.fetchCatalog()
            actions = Self.displayActions(from: catalog)
            message = nil
            hasLoaded = true
        } catch {
            actions = []
            message = QuickActionMessage(text: error.localizedDescription, tone: .error)
            hasLoaded = true
        }
    }

    private func perform(_ action: QuickActionDisplayData) async -> HomeOverview? {
        guard !isPerforming else {
            return nil
        }

        isPerforming = true
        performingActionID = action.id
        message = nil

        defer {
            isPerforming = false
            performingActionID = nil
        }

        do {
            let result = try await service.perform(action.request)
            switch result.status {
            case .success:
                message = QuickActionMessage(text: result.message, tone: .success)
            case .failure:
                message = QuickActionMessage(text: result.message, tone: .error)
            case .unknown:
                message = QuickActionMessage(text: result.message, tone: .warning)
            }

            return result.refreshedHomeOverview
        } catch {
            message = QuickActionMessage(text: error.localizedDescription, tone: .error)
            return nil
        }
    }

    private static func displayActions(from catalog: QuickActionCatalog) -> [QuickActionDisplayData] {
        catalog.actions.flatMap { action -> [QuickActionDisplayData] in
            switch action.id {
            case .closeGarage:
                return [
                    QuickActionDisplayData(
                        id: action.id.rawValue,
                        request: .closeGarage,
                        title: action.title,
                        subtitle: action.subtitle ?? "Close the main garage door.",
                        systemImage: "door.garage.closed",
                        isEnabled: action.isEnabled,
                        requiresConfirmation: action.requiresConfirmation
                    )
                ]
            case .turnOffAllLights:
                return [
                    QuickActionDisplayData(
                        id: action.id.rawValue,
                        request: .turnOffAllLights,
                        title: action.title,
                        subtitle: action.subtitle ?? "Turn off configured lights.",
                        systemImage: "lightbulb.slash",
                        isEnabled: action.isEnabled,
                        requiresConfirmation: action.requiresConfirmation
                    )
                ]
            case .turnOffLightGroup:
                if catalog.lightGroups.isEmpty {
                    return [
                        QuickActionDisplayData(
                            id: action.id.rawValue,
                            request: .turnOffLightGroup(groupId: ""),
                            title: action.title,
                            subtitle: "No curated light groups are configured.",
                            systemImage: "lightswitch.off",
                            isEnabled: false,
                            requiresConfirmation: action.requiresConfirmation
                        )
                    ]
                }

                return catalog.lightGroups.map { group in
                    QuickActionDisplayData(
                        id: "\(action.id.rawValue).\(group.id)",
                        request: .turnOffLightGroup(groupId: group.id),
                        title: "Turn Off \(group.name)",
                        subtitle: "Turn off this curated light group.",
                        systemImage: "lightswitch.off",
                        isEnabled: action.isEnabled,
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            case .unknown:
                return []
            }
        }
    }
}
