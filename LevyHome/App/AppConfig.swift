import Foundation

struct AppConfig: Equatable {
    static let defaultAPIBaseURLString = "https://levy-home.onrender.com"

    let apiBaseURL: URL
    let buildFlavor: BuildConfiguration
    let isDeveloperToolsEnabled: Bool
    let apnsEnvironment: APNSEnvironment?
    let appVersion: String?

    var isDebugBuild: Bool {
        buildFlavor.isDebugBuild
    }

    var apiAPNsEnvironment: APNsEnvironment {
        switch apnsEnvironment {
        case .sandbox:
            return .sandbox
        case .production:
            return .production
        case nil:
            return buildFlavor.isDebugBuild ? .sandbox : .production
        }
    }

    init(
        apiBaseURL: URL,
        buildFlavor: BuildConfiguration = .current,
        isDeveloperToolsEnabled: Bool? = nil,
        apnsEnvironment: APNSEnvironment? = nil,
        appVersion: String? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.buildFlavor = buildFlavor
        self.isDeveloperToolsEnabled = isDeveloperToolsEnabled ?? buildFlavor.defaultDeveloperToolsEnabled
        self.apnsEnvironment = apnsEnvironment
        self.appVersion = appVersion
    }

    init(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) {
        let buildFlavor = BuildConfiguration.current
        let rawAPIBaseURL = processInfo.environment["LEVY_HOME_API_BASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "LevyHomeAPIBaseURL") as? String

        self.init(
            apiBaseURL: Self.normalizedAPIBaseURL(from: rawAPIBaseURL),
            buildFlavor: buildFlavor,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
    }

    private static func normalizedAPIBaseURL(from rawValue: String?) -> URL {
        let trimmedValue = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard
            let trimmedValue,
            !trimmedValue.isEmpty,
            !trimmedValue.hasPrefix("$("),
            let url = URL(string: trimmedValue)
        else {
            return URL(string: defaultAPIBaseURLString)!
        }

        return url
    }
}

enum APNSEnvironment: String, Equatable {
    case sandbox
    case production
}
