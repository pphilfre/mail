import XCTest

@MainActor
final class DispatchUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWelcomeAndDrawerNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-showSampleInbox", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Dispatch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sign in with Google"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sign in with Zoho")).firstMatch.isEnabled)
        app.buttons["Explore sample mail"].tap()
        app.buttons["mailboxDrawerButton"].tap()
        app.buttons["Accounts"].tap()
        XCTAssertTrue(app.staticTexts["No accounts connected"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["mailboxDrawerButton"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Load remote images"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Swipe right"].exists)
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
        app.launchArguments = ["-showSampleInbox", "YES"]
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
