import AppIntents
import Foundation

final class SiriAppShortcutCommandRunner {
    private let commandService: SiriListCommandServicing
    private let residentName: () -> String?

    init(
        commandService: SiriListCommandServicing,
        residentName: @escaping () -> String?
    ) {
        self.commandService = commandService
        self.residentName = residentName
    }

    convenience init() {
        let apiClient = APIClient(baseURL: SiriExtensionConfiguration().apiBaseURL)
        self.init(
            commandService: SiriListCommandService(shoppingAPI: apiClient, toDoAPI: apiClient),
            residentName: { SiriSharedSettings().residentName }
        )
    }

    func execute(list: SiriListKind, title: String) async -> SiriListCommandResult {
        let resolution = SiriIntentResolver.resolveCommand(
            list: list,
            titles: [title],
            residentName: residentName()
        )

        switch resolution {
        case .command(let command):
            return await commandService.execute(command)
        case .requiresDeviceOwner:
            return .requiresDeviceOwner
        case .rejected:
            return .rejected
        }
    }
}

struct AddShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Shopping Item"
    static var openAppWhenRun = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("What should I add to Shopping?"))
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to Shopping")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SiriAppShortcutCommandRunner().execute(list: .shopping, title: item)
        return try result.appShortcutResult(for: .shopping)
    }
}

struct AddToDoItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add To Do Item"
    static var openAppWhenRun = false

    @Parameter(title: "Item", requestValueDialog: IntentDialog("What should I add to To Do?"))
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to To Do")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await SiriAppShortcutCommandRunner().execute(list: .toDo, title: item)
        return try result.appShortcutResult(for: .toDo)
    }
}

struct LevyHomeAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Add to \(.applicationName) Shopping",
                "Add an item to \(.applicationName) Shopping"
            ],
            shortTitle: "Add Shopping Item",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: AddToDoItemIntent(),
            phrases: [
                "Add to \(.applicationName) To Do",
                "Add a task to \(.applicationName)"
            ],
            shortTitle: "Add To Do Item",
            systemImageName: "checklist"
        )
    }
}

private enum SiriAppShortcutError: LocalizedError {
    case setupRequired
    case invalidItem
    case unavailable

    var errorDescription: String? {
        switch self {
        case .setupRequired:
            return "Choose Josh or Mallory in Levy Home before using this shortcut."
        case .invalidItem:
            return "Ask to add one nonempty item at a time."
        case .unavailable:
            return "Levy Home could not update the list. Try again later."
        }
    }
}

private extension SiriListCommandResult {
    func appShortcutResult(for list: SiriListKind) throws -> some IntentResult & ProvidesDialog {
        switch self {
        case .added:
            return .result(dialog: IntentDialog("Added to \(list.displayName)."))
        case .alreadyPresent, .restored:
            return .result(dialog: IntentDialog("\(list.displayName) is ready."))
        case .requiresDeviceOwner:
            throw SiriAppShortcutError.setupRequired
        case .rejected:
            throw SiriAppShortcutError.invalidItem
        case .notImplemented, .failed:
            throw SiriAppShortcutError.unavailable
        }
    }
}
