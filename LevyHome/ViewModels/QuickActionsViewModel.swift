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
    private let appLogStore: AppLogStore?
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

    init(service: QuickActionServicing, appLogStore: AppLogStore? = nil) {
        self.service = service
        self.appLogStore = appLogStore
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
        appLogStore?.record(
            level: .info,
            category: "Action",
            title: "\(action.title) selected",
            detail: "Action ID: \(action.id)"
        )

        guard canStart(action) else {
            return nil
        }

        if action.requiresConfirmation {
            pendingConfirmationAction = action
            appLogStore?.record(
                level: .info,
                category: "Action",
                title: "\(action.title) waiting for confirmation",
                detail: "No request has been sent yet."
            )
            return nil
        }

        return await perform(action)
    }

    func performImmediately(_ action: QuickActionDisplayData) async -> HomeOverview? {
        appLogStore?.record(
            level: .info,
            category: "Action",
            title: "\(action.title) triggered",
            detail: "Action ID: \(action.id). Sending immediately from a direct control."
        )

        guard canStart(action) else {
            return nil
        }

        pendingConfirmationAction = nil
        return await perform(action)
    }

    func performLightGroups(_ groupIds: [String], turnOn: Bool, title: String) async -> HomeOverview? {
        var seenGroupIds = Set<String>()
        let requestedGroupIds = groupIds.filter { groupId in
            guard !groupId.isEmpty, !seenGroupIds.contains(groupId) else {
                return false
            }

            seenGroupIds.insert(groupId)
            return true
        }

        guard !requestedGroupIds.isEmpty else {
            let reason = "\(title) does not have any configured light targets."
            message = QuickActionMessage(text: reason, tone: .warning)
            appLogStore?.record(
                level: .warning,
                category: "Action",
                title: "\(title) unavailable",
                detail: reason
            )
            return nil
        }

        guard !isBusy else {
            appLogStore?.record(
                level: .warning,
                category: "Action",
                title: "\(title) ignored",
                detail: "Quick actions are busy. Loading: \(isLoading), performing: \(isPerforming)."
            )
            return nil
        }

        let actionName = turnOn ? "All On" : "All Off"
        appLogStore?.record(
            level: .info,
            category: "Action",
            title: "\(title) \(actionName) requested",
            detail: "Targets: \(requestedGroupIds.joined(separator: ", "))"
        )

        isPerforming = true
        performingActionID = "\(turnOn ? "turn_on_light_group" : "turn_off_light_group").\(requestedGroupIds.joined(separator: "."))"
        message = nil

        defer {
            isPerforming = false
            performingActionID = nil
        }

        do {
            var refreshedOverview: HomeOverview?

            for groupId in requestedGroupIds {
                let request: QuickActionRequest = turnOn ? .turnOnLightGroup(groupId: groupId) : .turnOffLightGroup(groupId: groupId)
                let result = try await service.perform(request)

                switch result.status {
                case .success:
                    refreshedOverview = result.refreshedHomeOverview ?? refreshedOverview
                case .failure:
                    message = QuickActionMessage(text: result.message, tone: .error)
                    return nil
                case .unknown:
                    message = QuickActionMessage(text: result.message, tone: .warning)
                    return nil
                }
            }

            return refreshedOverview
        } catch {
            message = QuickActionMessage(text: error.localizedDescription, tone: .error)
            return nil
        }
    }

    func setThermostatTemperatures(low: Double, high: Double) async -> HomeOverview? {
        guard high - low >= ThermostatSetpointDraft.minimumDelta else {
            message = QuickActionMessage(
                text: "Thermostat high temperature must be at least 7° above the low temperature.",
                tone: .warning
            )
            return nil
        }

        guard !isBusy else {
            message = QuickActionMessage(text: "Thermostat controls are busy. Please wait a moment.", tone: .warning)
            return nil
        }

        isPerforming = true
        performingActionID = QuickActionID.setThermostatTemperature.rawValue
        message = nil

        defer {
            isPerforming = false
            performingActionID = nil
        }

        do {
            let result = try await service.perform(.setThermostatTemperature(low: low, high: high))

            switch result.status {
            case .success:
                return result.refreshedHomeOverview
            case .failure:
                message = QuickActionMessage(text: result.message, tone: .error)
                return nil
            case .unknown:
                message = QuickActionMessage(text: result.message, tone: .warning)
                return nil
            }
        } catch {
            message = QuickActionMessage(text: error.localizedDescription, tone: .error)
            return nil
        }
    }

    func confirmPendingAction() async -> HomeOverview? {
        guard let action = pendingConfirmationAction else {
            appLogStore?.record(
                level: .warning,
                category: "Action",
                title: "Confirmation ignored",
                detail: "There was no pending quick action to confirm."
            )
            return nil
        }

        return await confirm(action)
    }

    func confirm(_ action: QuickActionDisplayData) async -> HomeOverview? {
        pendingConfirmationAction = nil
        appLogStore?.record(
            level: .info,
            category: "Action",
            title: "\(action.title) confirmed",
            detail: "Sending confirmed action to the Levy Home API."
        )
        return await perform(action)
    }

    func cancelPendingConfirmation() {
        if let pendingConfirmationAction {
            appLogStore?.record(
                level: .info,
                category: "Action",
                title: "\(pendingConfirmationAction.title) cancelled",
                detail: "No request was sent."
            )
        }

        pendingConfirmationAction = nil
    }

    func reportUnavailableSelection(title: String, reason: String) {
        message = QuickActionMessage(text: reason, tone: .warning)
        appLogStore?.record(
            level: .warning,
            category: "Action",
            title: "\(title) unavailable",
            detail: reason
        )
    }

    func reportActionIssue(title: String, reason: String, tone: BannerTone = .error) {
        message = QuickActionMessage(text: reason, tone: tone)
        appLogStore?.record(
            level: tone == .error ? .error : .warning,
            category: "Action",
            title: "\(title) needs attention",
            detail: reason
        )
    }

    private func canStart(_ action: QuickActionDisplayData) -> Bool {
        guard action.isEnabled else {
            let reason = "\(action.title) is disabled in the quick-action catalog."
            message = QuickActionMessage(text: reason, tone: .warning)
            appLogStore?.record(
                level: .warning,
                category: "Action",
                title: "\(action.title) unavailable",
                detail: reason
            )
            return false
        }

        guard !isBusy else {
            appLogStore?.record(
                level: .warning,
                category: "Action",
                title: "\(action.title) ignored",
                detail: "Quick actions are busy. Loading: \(isLoading), performing: \(isPerforming)."
            )
            return false
        }

        return true
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
            let displayActions = Self.displayActions(from: catalog)
            actions = displayActions
            message = nil
            hasLoaded = true
            appLogStore?.record(
                level: .info,
                category: "Action",
                title: "Loaded quick actions",
                detail: Self.catalogLogDetail(displayActions)
            )
        } catch {
            guard !error.isTaskCancellation else {
                return
            }

            actions = []
            message = QuickActionMessage(text: error.localizedDescription, tone: .error)
            hasLoaded = true
            appLogStore?.record(
                level: .error,
                category: "Action",
                title: "Failed to load quick actions",
                detail: error.localizedDescription
            )
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
                message = nil
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
            case .openGarage:
                return [
                    QuickActionDisplayData(
                        id: action.id.rawValue,
                        request: .openGarage,
                        title: action.title,
                        subtitle: action.subtitle ?? "Open the main garage door.",
                        systemImage: "door.garage.open",
                        isEnabled: action.isEnabled,
                        requiresConfirmation: false
                    )
                ]
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
            case .turnOnLightGroup:
                if catalog.lightGroups.isEmpty {
                    return [
                        QuickActionDisplayData(
                            id: action.id.rawValue,
                            request: .turnOnLightGroup(groupId: ""),
                            title: action.title,
                            subtitle: "No curated light groups are configured.",
                            systemImage: "lightswitch.on",
                            isEnabled: false,
                            requiresConfirmation: action.requiresConfirmation
                        )
                    ]
                }

                return catalog.lightGroups.map { group in
                    QuickActionDisplayData(
                        id: "\(action.id.rawValue).\(group.id)",
                        request: .turnOnLightGroup(groupId: group.id),
                        title: "Turn On \(group.name)",
                        subtitle: "Turn on this curated light group.",
                        systemImage: "lightswitch.on",
                        isEnabled: action.isEnabled,
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
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
            case .setThermostatTemperature, .unknown:
                return []
            }
        }
    }

    private static func catalogLogDetail(_ actions: [QuickActionDisplayData]) -> String {
        guard !actions.isEmpty else {
            return "The API returned no usable quick actions."
        }

        return actions
            .map { action in
                let confirmation = action.requiresConfirmation ? "requires confirmation" : "direct"
                let enabled = action.isEnabled ? "enabled" : "disabled"
                return "\(action.id): \(enabled), \(confirmation)"
            }
            .joined(separator: "; ")
    }
}
