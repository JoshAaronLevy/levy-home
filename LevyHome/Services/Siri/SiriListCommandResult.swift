import Foundation

struct SiriListCommandItem: Equatable {
    let id: Int
    let title: String
    let list: SiriListKind

    init(item: ShoppingListItem) {
        id = item.id
        title = item.name
        list = .shopping
    }

    init(item: ToDoItem) {
        id = item.id
        title = item.name
        list = .toDo
    }
}

enum SiriListCommandResult: Equatable {
    case added(SiriListCommandItem)
    case alreadyPresent(SiriListCommandItem)
    case restored(SiriListCommandItem)
    case requiresDeviceOwner
    case notImplemented
    case rejected
    case failed
}
