import Intents
import OSLog

final class IntentHandler: INExtension, INAddTasksIntentHandling {
    private let logger = Logger(subsystem: "com.levyhome.app.intents", category: "Routing")
    private let sharedSettings = SiriSharedSettings()
    private let extensionConfiguration = SiriExtensionConfiguration()
    private lazy var apiClient = APIClient(baseURL: extensionConfiguration.apiBaseURL)
    private lazy var commandService = SiriListCommandService(
        shoppingAPI: apiClient,
        toDoAPI: apiClient
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
            let list = selectedList(in: intent.targetTaskList)
        else {
            completion(INAddTasksIntentResponse(code: .failure, userActivity: nil))
            return
        }

        let resolution = SiriIntentResolver.resolveCommand(
            list: list,
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

    private func selectedList(in taskList: INTaskList?) -> SiriListKind? {
        guard let taskList else {
            return nil
        }

        if let list = SiriListKind.allCases.first(where: {
            taskList.identifier == $0.siriTaskListIdentifier
        }) {
            return list
        }

        let title = taskList.title.spokenPhrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SiriListKind.allCases.first(where: {
            title.localizedCaseInsensitiveCompare($0.displayName) == .orderedSame
        })
    }

    private func response(for result: SiriListCommandResult) -> INAddTasksIntentResponse {
        switch result {
        case .added(let item), .alreadyPresent(let item), .restored(let item):
            let response = INAddTasksIntentResponse(code: .success, userActivity: nil)
            response.addedTasks = [task(for: item)]
            response.modifiedTaskList = taskList(for: item.list)
            return response
        case .requiresDeviceOwner:
            return INAddTasksIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil)
        case .notImplemented, .rejected, .failed:
            return INAddTasksIntentResponse(code: .failure, userActivity: nil)
        }
    }

    private func taskList(for list: SiriListKind) -> INTaskList {
        INTaskList(
            title: INSpeakableString(spokenPhrase: list.displayName),
            tasks: [],
            groupName: nil,
            createdDateComponents: nil,
            modifiedDateComponents: nil,
            identifier: list.siriTaskListIdentifier
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
            identifier: "\(item.list.rawValue)-\(item.id)",
            priority: .notFlagged
        )
    }
}
