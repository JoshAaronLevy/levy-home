import Foundation

enum SiriListKind: String, CaseIterable, Codable, Equatable {
    case shopping
    case toDo

    var displayName: String {
        switch self {
        case .shopping:
            return "Shopping"
        case .toDo:
            return "To Do"
        }
    }

    var siriTaskListIdentifier: String {
        switch self {
        case .shopping:
            return "levy-home-shopping"
        case .toDo:
            return "levy-home-todo"
        }
    }
}
