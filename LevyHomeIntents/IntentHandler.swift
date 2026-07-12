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

    func resolveTargetTaskList(
        for intent: INAddTasksIntent,
        with completion: @escaping (INAddTasksTargetTaskListResolutionResult) -> Void
    ) {
        let resolution = SiriIntentResolver.resolveTargetTaskList(
            identifier: intent.targetTaskList?.identifier,
            title: intent.targetTaskList?.title.spokenPhrase
        )

        switch resolution {
        case .resolved(let list):
            completion(taskListResolutionResult(for: .success(with: taskList(for: list))))
        case .disambiguationRequired:
            completion(taskListResolutionResult(for: .disambiguation(with: SiriListKind.allCases.map(taskList(for:)))))
        case .unsupported:
            completion(.unsupported())
        }
    }

    func resolveTaskTitles(
        for intent: INAddTasksIntent,
        with completion: @escaping ([INSpeakableStringResolutionResult]) -> Void
    ) {
        switch SiriIntentResolver.resolveTaskTitles(intent.taskTitles?.map(\.spokenPhrase)) {
        case .resolved(let title):
            completion([.success(with: INSpeakableString(spokenPhrase: title))])
        case .needsValue:
            completion([.needsValue()])
        case .unsupported:
            completion((intent.taskTitles ?? []).map { _ in .unsupported() })
        }
    }

    func resolveSpatialEventTrigger(
        for intent: INAddTasksIntent,
        with completion: @escaping (INSpatialEventTriggerResolutionResult) -> Void
    ) {
        completion(intent.spatialEventTrigger == nil ? .notRequired() : .unsupported())
    }

    func resolveTemporalEventTrigger(
        for intent: INAddTasksIntent,
        with completion: @escaping (INAddTasksTemporalEventTriggerResolutionResult) -> Void
    ) {
        completion(intent.temporalEventTrigger == nil ? .notRequired() : .unsupported())
    }

    func resolvePriority(
        for intent: INAddTasksIntent,
        with completion: @escaping (INTaskPriorityResolutionResult) -> Void
    ) {
        switch intent.priority {
        case .unknown, .notFlagged:
            completion(.notRequired())
        case .flagged:
            completion(.unsupported())
        @unknown default:
            completion(.unsupported())
        }
    }

    func confirm(
        intent: INAddTasksIntent,
        completion: @escaping (INAddTasksIntentResponse) -> Void
    ) {
        guard !hasUnsupportedMetadata(in: intent) else {
            completion(INAddTasksIntentResponse(code: .failure, userActivity: nil))
            return
        }

        guard let residentName = sharedSettings.residentName else {
            completion(INAddTasksIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
            return
        }

        switch command(for: intent, residentName: residentName) {
        case .command:
            completion(INAddTasksIntentResponse(code: .ready, userActivity: nil))
        case .requiresDeviceOwner:
            completion(INAddTasksIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
        case .rejected:
            completion(INAddTasksIntentResponse(code: .failure, userActivity: nil))
        }
    }

    func handle(
        intent: INAddTasksIntent,
        completion: @escaping (INAddTasksIntentResponse) -> Void
    ) {
        let targetListIdentifier = intent.targetTaskList?.identifier ?? "none"
        let taskCount = intent.taskTitles?.count ?? 0
        let apiConfigurationIsResolved = extensionConfiguration.apiBaseURL.host != nil

        // Do not log spoken titles. Siri can provide them as personal data.
        logger.notice(
            "Siri routing probe received: listIdentifier=\(targetListIdentifier, privacy: .public), taskCount=\(taskCount, privacy: .public), apiConfigurationIsResolved=\(apiConfigurationIsResolved, privacy: .public)"
        )

        guard let residentName = sharedSettings.residentName else {
            completion(INAddTasksIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
            return
        }

        guard !hasUnsupportedMetadata(in: intent) else {
            completion(INAddTasksIntentResponse(code: .failure, userActivity: nil))
            return
        }

        let resolution = command(for: intent, residentName: residentName)

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

    private func command(for intent: INAddTasksIntent, residentName: String) -> SiriIntentCommandResolution {
        guard case .resolved(let list) = SiriIntentResolver.resolveTargetTaskList(
            identifier: intent.targetTaskList?.identifier,
            title: intent.targetTaskList?.title.spokenPhrase
        ) else {
            return .rejected
        }

        guard case .resolved(let title) = SiriIntentResolver.resolveTaskTitles(
            intent.taskTitles?.map(\.spokenPhrase)
        ) else {
            return .rejected
        }

        return SiriIntentResolver.resolveCommand(
            list: list,
            titles: [title],
            residentName: residentName
        )
    }

    private func hasUnsupportedMetadata(in intent: INAddTasksIntent) -> Bool {
        intent.spatialEventTrigger != nil
            || intent.temporalEventTrigger != nil
            || intent.priority == .flagged
    }

    private func taskListResolutionResult(
        for result: INTaskListResolutionResult
    ) -> INAddTasksTargetTaskListResolutionResult {
        INAddTasksTargetTaskListResolutionResult(taskListResolutionResult: result)
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
