import Foundation

enum SiriIntentCommandResolution: Equatable {
    case command(SiriListCommand)
    case requiresDeviceOwner
    case rejected
}

enum SiriIntentResolver {
    static func resolveCommand(
        list: SiriListKind,
        titles: [String],
        residentName: String?
    ) -> SiriIntentCommandResolution {
        guard let residentName else {
            return .requiresDeviceOwner
        }

        guard titles.count == 1 else {
            return .rejected
        }

        let title = titles[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return .rejected
        }

        return .command(
            SiriListCommand(
                list: list,
                title: title,
                residentName: residentName
            )
        )
    }
}
