import Foundation

struct SiriExtensionConfiguration: Equatable {
    static let defaultAPIBaseURL = URL(string: "https://levy-home.onrender.com")!

    let apiBaseURL: URL

    init(bundle: Bundle = .main) {
        self.init(rawAPIBaseURL: bundle.object(forInfoDictionaryKey: "LevyHomeAPIBaseURL") as? String)
    }

    init(rawAPIBaseURL: String?) {
        let trimmedValue = rawAPIBaseURL?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard
            let trimmedValue,
            !trimmedValue.isEmpty,
            !trimmedValue.hasPrefix("$("),
            let url = URL(string: trimmedValue),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            apiBaseURL = Self.defaultAPIBaseURL
            return
        }

        apiBaseURL = url
    }
}
