import SwiftUI
import XCTest
@testable import LevyHome

@MainActor
final class ThemePreferenceViewModelTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()

        suiteName = "ThemePreferenceViewModelTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil

        super.tearDown()
    }

    func testDefaultsToSystemPreference() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.preference, .system)
        XCTAssertNil(viewModel.preferredColorScheme)
        XCTAssertEqual(viewModel.selectedTitle, "System")
    }

    func testSelectingLightForcesLightColorSchemeAndPersists() {
        let firstViewModel = makeViewModel()

        firstViewModel.select(.light)

        XCTAssertEqual(firstViewModel.preference, .light)
        XCTAssertEqual(firstViewModel.preferredColorScheme, .light)

        let secondViewModel = makeViewModel()
        XCTAssertEqual(secondViewModel.preference, .light)
        XCTAssertEqual(secondViewModel.preferredColorScheme, .light)
    }

    func testSelectingDarkForcesDarkColorSchemeAndPersists() {
        let firstViewModel = makeViewModel()

        firstViewModel.select(.dark)

        XCTAssertEqual(firstViewModel.preference, .dark)
        XCTAssertEqual(firstViewModel.preferredColorScheme, .dark)

        let secondViewModel = makeViewModel()
        XCTAssertEqual(secondViewModel.preference, .dark)
        XCTAssertEqual(secondViewModel.preferredColorScheme, .dark)
    }

    func testInvalidStoredValueFallsBackToSystem() {
        userDefaults.set("sepia", forKey: "themePreference")

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.preference, .system)
        XCTAssertNil(viewModel.preferredColorScheme)
    }

    private func makeViewModel() -> ThemePreferenceViewModel {
        ThemePreferenceViewModel(
            service: ThemePreferenceService(userDefaults: userDefaults)
        )
    }
}
