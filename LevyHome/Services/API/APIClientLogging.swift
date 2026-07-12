import Foundation

enum AppLogLevel: String, Codable, Equatable {
    case info
    case success
    case warning
    case error
}

protocol APIClientLogging: AnyObject {
    func record(
        level: AppLogLevel,
        category: String,
        title: String,
        detail: String?
    )
}
