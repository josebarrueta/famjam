import XCTest

final class FamilyAppUITests: XCTestCase {
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
