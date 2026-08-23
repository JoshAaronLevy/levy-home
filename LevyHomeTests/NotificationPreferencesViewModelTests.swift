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

    func testLoadsNotificationPreferencesEnabledByDefault() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.preferences.count, 13)
        XCTAssertEqual(
            viewModel.preferences.map(\.category),
            [
                .garageOpened,
                .garageClosed,
                .garageLeftOpen,
                .garageAfterHours,
                .garageStillOpenAt10PM,
                .laundry,
                .freezer,
                .refrigerator,
                .partnerPresence,
                .doorbell,
                .thermostatSetpointHigh,
                .weatherAlerts,
                .lightingAutomation
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

    func testSyncSuccessBuildsProviderAwarePreferenceRequest() async {
        let service = MockNotificationPreferencesService()
        let viewModel = NotificationPreferencesViewModel(service: service)

        await viewModel.syncPreferences(
            deviceToken: "abc123",
            environment: .sandbox
        )

        XCTAssertEqual(viewModel.syncLabel, "Synced")
        XCTAssertEqual(viewModel.syncTone, .success)
        XCTAssertEqual(viewModel.developerSyncMessage, "Preference sync succeeded.")
        XCTAssertEqual(service.syncRequests.count, 1)
        XCTAssertEqual(service.syncRequests.first?.deviceToken, "abc123")
        XCTAssertEqual(service.syncRequests.first?.provider, .apns)
        XCTAssertEqual(service.syncRequests.first?.environment, .sandbox)
        XCTAssertEqual(service.syncRequests.first?.preferences.map(\.category), NotificationPreferencesService.defaultPreferences.map(\.category))
    }

    func testSyncFailureKeepsLocalPreferencesAndShowsDegradedState() async {
        let service = MockNotificationPreferencesService(error: APIError.server(statusCode: 503, message: "Preference API down."))
        let viewModel = NotificationPreferencesViewModel(service: service)
        viewModel.setPreference(viewModel.preferences[0], isEnabled: false)

        await viewModel.syncPreferences(
            deviceToken: "abc123",
            environment: .sandbox
        )

        XCTAssertFalse(viewModel.preferences[0].isEnabled)
        XCTAssertEqual(viewModel.syncLabel, "Not synced")
        XCTAssertEqual(viewModel.syncTone, .warning)
        XCTAssertEqual(viewModel.syncDetail, "Saved on this device. API sync is currently unavailable.")
        XCTAssertEqual(viewModel.developerSyncMessage, "Preference sync failed: Preference API down.")
    }

    func testSyncWithoutDeviceTokenIsSkippedWithoutLosingLocalState() async {
        let service = MockNotificationPreferencesService()
        let viewModel = NotificationPreferencesViewModel(service: service)
        viewModel.setPreference(viewModel.preferences[0], isEnabled: false)

        await viewModel.syncPreferences(
            deviceToken: nil,
            environment: .sandbox
        )

        XCTAssertFalse(viewModel.preferences[0].isEnabled)
        XCTAssertEqual(viewModel.syncLabel, "Not synced")
        XCTAssertEqual(viewModel.syncTone, .neutral)
        XCTAssertEqual(viewModel.developerSyncMessage, "Preference sync skipped: no APNs token is available.")
        XCTAssertTrue(service.syncRequests.isEmpty)
    }

    private func makeViewModel() -> NotificationPreferencesViewModel {
        NotificationPreferencesViewModel(
            service: NotificationPreferencesService(userDefaults: userDefaults)
        )
    }
}

private final class MockNotificationPreferencesService: NotificationPreferencesServicing {
    private var storedPreferences = NotificationPreferencesService.defaultPreferences
    private let error: Error?
    private(set) var syncRequests: [NotificationPreferencesUpdateRequest] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func loadPreferences() -> [NotificationPreference] {
        storedPreferences
    }

    func setPreference(_ category: NotificationPreferenceCategory, isEnabled: Bool) {
        storedPreferences = storedPreferences.map { preference in
            guard preference.category == category else {
                return preference
            }

            return NotificationPreference(
                category: preference.category,
                isEnabled: isEnabled,
                title: preference.title,
                detail: preference.detail
            )
        }
    }

    func syncPreferences(
        deviceToken: String,
        provider: PushProvider,
        environment: APNsEnvironment
    ) async throws -> NotificationPreferencesResponse {
        let request = NotificationPreferencesUpdateRequest(
            preferences: storedPreferences.map {
                NotificationPreferenceUpdate(category: $0.category, isEnabled: $0.isEnabled)
            },
            deviceToken: deviceToken,
            provider: provider,
            environment: environment
        )
        syncRequests.append(request)

        if let error {
            throw error
        }

        return NotificationPreferencesResponse(
            ok: true,
            preferences: storedPreferences,
            syncedAt: "2026-06-12T14:00:00Z"
        )
    }
}
