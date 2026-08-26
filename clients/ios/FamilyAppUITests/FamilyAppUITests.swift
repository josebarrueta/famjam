import XCTest

@MainActor
final class FamilyAppUITests: XCTestCase {
    func testLoginDoesNotAskForAManualInvitationCode() {
        let app = XCUIApplication()
        app.launchEnvironment["FAMJAM_DATA_MODE"] = "remote"
        app.launchEnvironment["FAMJAM_REMOTE_BASE_URL"] = "http://127.0.0.1:3199"
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to FamJam"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Continue with Google"].exists)
        XCTAssertFalse(app.textFields["Invitation code (optional)"].exists)
    }

    func testParentCanOpenTheLocalScheduleAndFamilyTabs() {
        let app = XCUIApplication()
        app.launchEnvironment["FAMJAM_DATA_MODE"] = "local"
        app.launch()

        XCTAssertTrue(app.navigationBars["FamJam"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Let's jam!"].exists)
        XCTAssertTrue(app.tabBars.buttons["Schedule"].exists)
        XCTAssertTrue(app.tabBars.buttons["Family"].exists)
        XCTAssertTrue(app.tabBars.buttons["Alerts"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)

        app.tabBars.buttons["Family"].tap()
        XCTAssertTrue(app.navigationBars["Family"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your home team"].exists)
    }
}
