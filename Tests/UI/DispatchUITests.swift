import XCTest

@MainActor
final class DispatchUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEmptyInboxAndAccountsAreHonest() {
        let app = XCUIApplication()
        app.launchArguments = ["-showSampleInbox", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your inbox starts here"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Accounts"].tap()
        XCTAssertTrue(app.staticTexts["No accounts connected"].waitForExistence(timeout: 5))
    }

    func testSampleMessageOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-showSampleInbox", "YES"]
        app.launch()
        let row = app.staticTexts["A quieter inbox"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["Sample message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["alex@example.com"].exists)
    }

    func testComposeDraftSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-showSampleInbox", "NO"]
        app.launch()
        app.buttons["composeButton"].tap()
        let subject = app.textFields["composeSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        let title = "Offline draft \(UUID().uuidString.prefix(8))"
        subject.tap()
        subject.typeText(title)
        app.buttons["saveDraftButton"].tap()
        app.terminate()
        app.launch()
        app.staticTexts["On-device drafts"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        app.staticTexts[title].tap()
        XCTAssertEqual(app.textFields["composeSubject"].value as? String, title)
    }
}
