import Foundation

enum SiriListCommandResult: Equatable {
    case requiresDeviceOwner
    case notImplemented
    case rejected
    case failed
}
