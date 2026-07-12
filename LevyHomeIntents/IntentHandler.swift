import Intents
import OSLog

final class IntentHandler: INExtension, INAddTasksIntentHandling {
    private let logger = Logger(subsystem: "com.levyhome.app.intents", category: "Routing")
    private let sharedSettings = SiriSharedSettings()
    private let extensionConfiguration = SiriExtensionConfiguration()
    private lazy var commandService = SiriListCommandService(
        shoppingAPI: APIClient(baseURL: extensionConfiguration.apiBaseURL)
    )

    override func handler(for intent: INIntent) -> Any {
        self
    }

    func handle(
        intent: INAddTasksIntent,
        completion: @escaping (INAddTasksIntentResponse) -> Void
    ) {
        let targetListIdentifier = intent.targetTaskList?.identifier ?? "none"
        let taskCount = intent.taskTitles?.count ?? 0
        let apiConfigurationIsResolved = extensionConfiguration.apiBaseURL.host != nil

        // Stage 1 deliberately proves routing only. Do not log spoken titles or mutate a list.
        logger.notice(
            "Siri routing probe received: listIdentifier=\(targetListIdentifier, privacy: .public), taskCount=\(taskCount, privacy: .public), apiConfigurationIsResolved=\(apiConfigurationIsResolved, privacy: .public)"
        )

        guard let residentName = sharedSettings.residentName else {
            completion(INAddTasksIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
            return
        }

        guard
            let taskTitles = intent.taskTitles,
            shoppingListWasSelected(in: intent.targetTaskList)
        else {
            completion(INAddTasksIntentResponse(code: .failure, userActivity: nil))
            return
        }

        let resolution = SiriIntentResolver.resolveCommand(
            list: .shopping,
            titles: taskTitles.map(\.spokenPhrase),
            residentName: residentName
        )

        guard case .command(let command) = resolution else {
            let responseCode: INAddTasksIntentResponseCode = resolution == .requiresDeviceOwner
                ? .failureRequiringAppLaunch
                : .failure
            completion(INAddTasksIntentResponse(code: responseCode, userActivity: nil))
            return
        }

        Task { [weak self] in
            guard let self else {
                completion(INAddTasksIntentResponse(code: .failure, userActivity: nil))
                return
            }

            let result = await commandService.execute(command)
            completion(response(for: result))
        }
    }

    private func shoppingListWasSelected(in taskList: INTaskList?) -> Bool {
        guard let taskList else {
            return false
        }

        if taskList.identifier == SiriListKind.shopping.siriTaskListIdentifier {
            return true
        }

        return taskList.title.spokenPhrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(SiriListKind.shopping.displayName) == .orderedSame
    }

    private func response(for result: SiriListCommandResult) -> INAddTasksIntentResponse {
        switch result {
        case .added(let item), .alreadyPresent(let item), .restored(let item):
            let response = INAddTasksIntentResponse(code: .success, userActivity: nil)
            response.addedTasks = [task(for: item)]
            response.modifiedTaskList = shoppingTaskList()
            return response
        case .requiresDeviceOwner:
            return INAddTasksIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil)
        case .notImplemented, .rejected, .failed:
            return INAddTasksIntentResponse(code: .failure, userActivity: nil)
        }
    }

    private func shoppingTaskList() -> INTaskList {
        INTaskList(
            title: INSpeakableString(spokenPhrase: SiriListKind.shopping.displayName),
            tasks: [],
            groupName: nil,
            createdDateComponents: nil,
            modifiedDateComponents: nil,
            identifier: SiriListKind.shopping.siriTaskListIdentifier
        )
    }

    private func task(for item: SiriListCommandItem) -> INTask {
        INTask(
            title: INSpeakableString(spokenPhrase: item.title),
            status: .notCompleted,
            taskType: .completable,
            spatialEventTrigger: nil,
            temporalEventTrigger: nil,
            createdDateComponents: nil,
            modifiedDateComponents: nil,
            identifier: "shopping-\(item.id)",
            priority: .notFlagged
        )
    }
}
