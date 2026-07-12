import XCTest
@testable import LevyHome

final class SiriExtensionConfigurationTests: XCTestCase {
    func testUsesResolvedExtensionBundleAPIURL() {
        let configuration = SiriExtensionConfiguration(
            rawAPIBaseURL: "https://example.test/api/"
        )

        XCTAssertEqual(configuration.apiBaseURL.absoluteString, "https://example.test/api")
    }

    func testRejectsAnUnresolvedBuildSettingPlaceholder() {
        let configuration = SiriExtensionConfiguration(
            rawAPIBaseURL: "$(LEVY_HOME_API_BASE_URL)"
        )

        XCTAssertEqual(configuration.apiBaseURL, SiriExtensionConfiguration.defaultAPIBaseURL)
    }
}
