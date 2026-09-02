import XCTest

@MainActor
final class FamilyAppUITests: XCTestCase {
    func testLoginDoesNotAskForAManualInvitationCode() {
        let app = XCUIApplication()
        app.launchEnvironment["RALLYROO_DATA_MODE"] = "remote"
        app.launchEnvironment["RALLYROO_REMOTE_BASE_URL"] = "http://127.0.0.1:3199"
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to Rallyroo"].waitForExistence(timeout: 10))
        let appleButton = app.buttons["Continue with Apple"]
        let googleButton = app.buttons["Continue with Google"]
        XCTAssertTrue(appleButton.exists)
        XCTAssertTrue(googleButton.exists)
        XCTAssertEqual(appleButton.frame.width, googleButton.frame.width, accuracy: 1)
        XCTAssertEqual(appleButton.frame.height, googleButton.frame.height, accuracy: 1)
        XCTAssertFalse(app.textFields["Invitation code (optional)"].exists)
    }

    func testUserCanSignOutFromSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["RALLYROO_DATA_MODE"] = "local"
        app.launch()

        XCTAssertTrue(app.navigationBars["Rallyroo"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()

        let signOut = app.buttons["Sign Out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()

        let confirmation = app.buttons["confirm-sign-out"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.staticTexts["Welcome to Rallyroo"].waitForExistence(timeout: 5))
    }

    func testParentCanOpenTheLocalScheduleAndFamilyTabs() {
        let app = XCUIApplication()
        app.launchEnvironment["RALLYROO_DATA_MODE"] = "local"
        app.launch()

        XCTAssertTrue(app.navigationBars["Rallyroo"].waitForExistence(timeout: 10))
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
