import XCTest
@testable import FamilyCore

final class ConflictAlertPreferencesTests: XCTestCase {
    func testConflictAlertsAreEnabledByDefault() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = ConflictAlertPreferences(defaults: defaults)

        XCTAssertTrue(preferences.areConflictAlertsEnabled)
    }

    func testStoresDisabledConflictAlerts() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = ConflictAlertPreferences(defaults: defaults)

        preferences.areConflictAlertsEnabled = false

        XCTAssertFalse(ConflictAlertPreferences(defaults: defaults).areConflictAlertsEnabled)
    }
}
