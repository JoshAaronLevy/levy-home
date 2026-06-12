import Foundation

enum BuildConfiguration: String, Equatable {
    case debug
    case release

    static var current: BuildConfiguration {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    var isDebugBuild: Bool {
        self == .debug
    }

    var defaultDeveloperToolsEnabled: Bool {
        isDebugBuild
    }
}
