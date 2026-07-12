import Intents
import OSLog

final class IntentHandler: INExtension, INAddTasksIntentHandling {
    private let logger = Logger(subsystem: "com.levyhome.app.intents", category: "Routing")
    private let sharedSettings = SiriSharedSettings()
    private let extensionConfiguration = SiriExtensionConfiguration()

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

        guard sharedSettings.residentName != nil else {
            completion(INAddTasksIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
            return
        }

        completion(INAddTasksIntentResponse(code: .failure, userActivity: nil))
    }
}
