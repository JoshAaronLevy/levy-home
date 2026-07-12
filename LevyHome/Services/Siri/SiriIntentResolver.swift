import Foundation

enum SiriIntentCommandResolution: Equatable {
    case command(SiriListCommand)
    case requiresDeviceOwner
    case rejected
}

enum SiriTargetTaskListResolution: Equatable {
    case resolved(SiriListKind)
    case disambiguationRequired
    case unsupported
}

enum SiriTaskTitlesResolution: Equatable {
    case resolved(String)
    case needsValue
    case unsupported
}

enum SiriIntentResolver {
    static func resolveTargetTaskList(
        identifier: String?,
        title: String?
    ) -> SiriTargetTaskListResolution {
        let listForIdentifier = SiriListKind.allCases.first {
            identifier == $0.siriTaskListIdentifier
        }
        let normalizedTitle = normalized(title)
        let listForTitle = SiriListKind.allCases.first { list in
            list.acceptedTaskListNames.contains { normalized($0) == normalizedTitle }
        }

        switch (listForIdentifier, listForTitle) {
        case let (.some(identifierList), .some(titleList)) where identifierList != titleList:
            return .disambiguationRequired
        case let (.some(list), _), let (_, .some(list)):
            return .resolved(list)
        case (.none, .none) where identifier == nil && normalizedTitle.isEmpty:
            return .disambiguationRequired
        case (.none, .none):
            return .unsupported
        }
    }

    static func resolveTaskTitles(_ titles: [String]?) -> SiriTaskTitlesResolution {
        guard let titles, !titles.isEmpty else {
            return .needsValue
        }

        guard titles.count == 1 else {
            return .unsupported
        }

        let title = titles[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? .needsValue : .resolved(title)
    }

    static func resolveCommand(
        list: SiriListKind,
        titles: [String],
        residentName: String?
    ) -> SiriIntentCommandResolution {
        guard let residentName else {
            return .requiresDeviceOwner
        }

        guard case .resolved(let title) = resolveTaskTitles(titles) else {
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

    private static func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .localizedLowercase ?? ""
    }
}
