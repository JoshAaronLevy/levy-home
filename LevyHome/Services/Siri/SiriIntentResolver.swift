import Foundation

enum SiriIntentResolver {
    static func makeCommand(
        list: SiriListKind,
        title: String,
        residentName: String?
    ) -> SiriListCommandResult {
        guard residentName != nil else {
            return .requiresDeviceOwner
        }

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected
        }

        return .notImplemented
    }
}
