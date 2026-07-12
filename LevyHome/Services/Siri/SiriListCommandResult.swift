import Foundation

struct SiriListCommandItem: Equatable {
    let id: Int
    let title: String

    init(item: ShoppingListItem) {
        id = item.id
        title = item.name
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
