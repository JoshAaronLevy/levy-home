import XCTest
@testable import LevyHome

final class SiriResidentStoreTests: XCTestCase {
    private var legacySuiteName: String!
    private var sharedSuiteName: String!
    private var legacyDefaults: UserDefaults!
    private var sharedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()

        legacySuiteName = "SiriResidentStoreTests.legacy.\(UUID().uuidString)"
        sharedSuiteName = "SiriResidentStoreTests.shared.\(UUID().uuidString)"
        legacyDefaults = UserDefaults(suiteName: legacySuiteName)
        sharedDefaults = UserDefaults(suiteName: sharedSuiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
    }

    override func tearDown() {
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
        legacyDefaults = nil
        sharedDefaults = nil
        legacySuiteName = nil
        sharedSuiteName = nil

        super.tearDown()
    }

    func testMigratesLegacyDeviceOwnerBeforeSharedStoreIsRead() {
        legacyDefaults.set("Mallory", forKey: ResidentPreference.storageKey)

        ResidentPreference.migrateFromStandardDefaults(
            standardDefaults: legacyDefaults,
            sharedDefaults: sharedDefaults
        )

        XCTAssertEqual(SiriSharedSettings(userDefaults: sharedDefaults).residentName, "Mallory")
        XCTAssertTrue(sharedDefaults.bool(forKey: ResidentPreference.migrationKey))
    }

    func testMigrationDoesNotReplaceAnExistingSharedDeviceOwner() {
        legacyDefaults.set("Josh", forKey: ResidentPreference.storageKey)
        sharedDefaults.set("Mallory", forKey: ResidentPreference.storageKey)

        ResidentPreference.migrateFromStandardDefaults(
            standardDefaults: legacyDefaults,
            sharedDefaults: sharedDefaults
        )

        XCTAssertEqual(SiriSharedSettings(userDefaults: sharedDefaults).residentName, "Mallory")
    }

    func testEmptySharedDeviceOwnerRequiresSetup() {
        sharedDefaults.set("   ", forKey: ResidentPreference.storageKey)

        XCTAssertNil(SiriSharedSettings(userDefaults: sharedDefaults).residentName)
    }
}
