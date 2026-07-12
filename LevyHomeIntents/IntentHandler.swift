import Intents
import OSLog

final class IntentHandler: INExtension, INAddTasksIntentHandling {
    private let logger = Logger(subsystem: "com.levyhome.app.intents", category: "Routing")

    override func handler(for intent: INIntent) -> Any {
        self
    }

    func handle(
        intent: INAddTasksIntent,
        completion: @escaping (INAddTasksIntentResponse) -> Void
    ) {
        let targetListIdentifier = intent.targetTaskList?.identifier ?? "none"
        let taskCount = intent.taskTitles?.count ?? 0

        // Stage 1 deliberately proves routing only. Do not log spoken titles or mutate a list.
        logger.notice(
            "Siri routing probe received: listIdentifier=\(targetListIdentifier, privacy: .public), taskCount=\(taskCount, privacy: .public)"
        )

        completion(INAddTasksIntentResponse(code: .failure, userActivity: nil))
    }
}
