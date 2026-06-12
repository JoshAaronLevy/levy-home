import XCTest
@testable import LevyHome

@MainActor
final class NotificationPreferencesViewModelTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()

        suiteName = "NotificationPreferencesViewModelTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil

        super.tearDown()
    }

    func testLoadsFiveGaragePreferencesEnabledByDefault() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.preferences.count, 5)
        XCTAssertEqual(
            viewModel.preferences.map(\.category),
            [
                .garageOpened,
                .garageClosed,
                .garageLeftOpen,
                .garageAfterHours,
                .garageStillOpenAt10PM
            ]
        )
        XCTAssertTrue(viewModel.preferences.allSatisfy(\.isEnabled))
    }

    func testTogglingPreferenceUpdatesCurrentState() {
        let viewModel = makeViewModel()
        let preference = viewModel.preferences[2]

        viewModel.setPreference(preference, isEnabled: false)

        XCTAssertEqual(viewModel.preferences[2].category, .garageLeftOpen)
        XCTAssertFalse(viewModel.preferences[2].isEnabled)
        XCTAssertTrue(viewModel.preferences[0].isEnabled)
    }

    func testToggledPreferencesPersistAcrossViewModelInstances() {
        let firstViewModel = makeViewModel()
        firstViewModel.setPreference(firstViewModel.preferences[0], isEnabled: false)
        firstViewModel.setPreference(firstViewModel.preferences[4], isEnabled: false)

        let secondViewModel = makeViewModel()

        XCTAssertFalse(secondViewModel.preferences[0].isEnabled)
        XCTAssertTrue(secondViewModel.preferences[1].isEnabled)
        XCTAssertFalse(secondViewModel.preferences[4].isEnabled)
    }

    private func makeViewModel() -> NotificationPreferencesViewModel {
        NotificationPreferencesViewModel(
            service: NotificationPreferencesService(userDefaults: userDefaults)
        )
    }
}
