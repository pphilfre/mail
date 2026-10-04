import XCTest

@MainActor
final class DispatchUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGroupedBulkArchiveCanBeUndoneWithoutProviderAccess() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launch()
        XCTAssertTrue(app.staticTexts["inboxResultCount"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["inboxResultCount"].label, "1 conversation")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Feature wave inbox"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["selectMailButton"].tap()
        app.buttons["Select all"].tap()
        XCTAssertTrue(app.staticTexts["2 loaded messages selected"].exists)
        app.buttons["Archive"].tap()
        let undo = app.buttons["triageUndo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cachedMessage-latest"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["inboxResultCount"].label, "1 conversation")
    }

    func testSearchOperatorsAndFiltersFindCachedConversation() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launch()
        app.buttons["searchButton"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("from:reader-fixture subject:layout")
        XCTAssertTrue(app.staticTexts["2 results"].waitForExistence(timeout: 5))
        app.buttons["Attachments"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchNoResults"].firstMatch.waitForExistence(timeout: 5))
    }

    func testComposerShowsInvalidRecipientsBeforeSend() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launch()
        app.buttons["composeButton"].tap()
        let recipient = app.textFields["composeTo"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 5))
        recipient.tap(); recipient.typeText("not-an-address")
        XCTAssertTrue(app.staticTexts["invalidRecipients-To"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sendButton"].isEnabled)
        app.textFields["composeSubject"].tap()
        let edit = app.buttons["Edit To recipients"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(recipient.waitForExistence(timeout: 5))
        XCTAssertEqual(recipient.value as? String, "not-an-address")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Recipient validation"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testWelcomeAndDrawerNavigation() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "NO"
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Dispatch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sign in with Google"].exists)
        XCTAssertTrue(app.staticTexts["Gmail, for now. Zoho is on its way."].exists)
        app.buttons["Explore sample mail"].tap()
        XCTAssertTrue(app.buttons["mailboxDrawerButton"].waitForExistence(timeout: 5))
        app.buttons["mailboxDrawerButton"].tap()
        app.buttons["mailboxProfileMenu"].tap()
        app.buttons["Accounts"].tap()
        XCTAssertTrue(app.staticTexts["No accounts connected"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["mailboxDrawerButton"].tap()
        app.buttons["mailboxProfileMenu"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Load remote images"].waitForExistence(timeout: 5))
        if !app.staticTexts["Swipe right"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Swipe right"].exists)
    }

    func testMailboxSheetClosesAndProfileMenuOpensSettings() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launch()
        attachScreenshot("Inbox redesign", app: app)
        app.buttons["mailboxDrawerButton"].tap()
        let close = app.buttons["closeMailboxesButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        attachScreenshot("Mailbox sheet", app: app)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composeButton"].isHittable)
        app.buttons["profileMenuButton"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Load remote images"].waitForExistence(timeout: 5))
        attachScreenshot("Settings redesign", app: app)
    }

    func testQuickUnreadFilterUpdatesAfterReadingAndCanReturnToAll() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launch()
        app.buttons["inboxFilter-Unread"].tap()
        XCTAssertTrue(app.staticTexts["A quieter inbox"].exists)
        XCTAssertFalse(app.staticTexts["Re: Saturday plans"].exists)
        app.staticTexts["A quieter inbox"].tap()
        XCTAssertTrue(app.staticTexts["Sample message"].waitForExistence(timeout: 5))
        let bodyText = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hi Freddie,")).firstMatch
        XCTAssertTrue(bodyText.waitForExistence(timeout: 15), "The sample message body must finish rendering before capture")
        attachScreenshot("Reader redesign", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.staticTexts["A quieter inbox"].exists)
        app.buttons["inboxFilter-All"].tap()
        XCTAssertTrue(app.staticTexts["A quieter inbox"].exists)
        XCTAssertTrue(app.staticTexts["Re: Saturday plans"].exists)
    }

    func testSavingDraftShowsConfirmationAndStillOpensSavedDraft() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launch()
        app.buttons["composeButton"].tap()
        let subject = app.textFields["composeSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        let title = "Confirmed draft \(UUID().uuidString.prefix(8))"
        subject.tap(); subject.typeText(title)
        app.buttons["saveDraftButton"].tap()
        XCTAssertTrue(app.staticTexts["Draft saved"].waitForExistence(timeout: 5))
        attachScreenshot("Draft confirmation", app: app)
        let dismissConfirmation = app.buttons["Dismiss confirmation"]
        if dismissConfirmation.exists { dismissConfirmation.tap() }
        app.descendants(matching: .any)["draftsShortcut"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
    }

    func testSampleMessageOpens() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launch()
        let row = app.staticTexts["A quieter inbox"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["Sample message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["alex@example.com"].exists)
    }

    func testLocalSearchFindsSampleMailAndShowsNoResults() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launch()
        app.buttons["searchButton"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("quieter")
        let results = app.descendants(matching: .any)["searchResultsList"]
        let match = results.descendants(matching: .any)["searchResultSample-alex@example.com"]
        XCTAssertTrue(match.waitForExistence(timeout: 5), results.debugDescription)
        XCTAssertFalse(results.descendants(matching: .any)["searchResultSample-studio@example.com"].exists)
        match.tap()
        XCTAssertTrue(app.staticTexts["Sample message"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        search.tap()
        search.typeText("zzzznomatch")
        XCTAssertTrue(results.descendants(matching: .any)["searchNoResults"].waitForExistence(timeout: 5), results.debugDescription)
    }

    func testComposeDraftSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
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
        app.descendants(matching: .any)["draftsShortcut"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        app.staticTexts[title].tap()
        XCTAssertEqual(app.textFields["composeSubject"].value as? String, title)
    }

    func testDraftAutosaveSurvivesRelaunchWithoutPressingSave() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launch()
        app.buttons["composeButton"].tap()
        let subject = app.textFields["composeSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        let title = "Autosaved \(UUID().uuidString.prefix(8))"
        subject.tap(); subject.typeText(title)
        XCTAssertTrue(app.staticTexts["draftAutosaveStatus"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.descendants(matching: .any)["draftsShortcut"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
    }

    func testSampleUnreadMailboxFiltersReadMessages() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launch()
        app.buttons["mailboxDrawerButton"].tap()
        app.buttons["mailbox-Unread"].tap()
        XCTAssertTrue(app.staticTexts["A quieter inbox"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Re: Saturday plans"].exists)
    }

    func testDraftsMailboxShowsLocalDraftAndOpensComposer() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launch()
        app.buttons["composeButton"].tap()
        let subject = app.textFields["composeSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        let title = "Unified draft \(UUID().uuidString.prefix(8))"
        subject.tap(); subject.typeText(title)
        app.buttons["saveDraftButton"].tap()
        app.buttons["mailboxDrawerButton"].tap()
        app.buttons["mailbox-Drafts"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        app.staticTexts[title].tap()
        XCTAssertEqual(app.textFields["composeSubject"].value as? String, title)
    }

    func testConversationStartsWithOpenedMessageExpandedAndCanRevealEarlierMail() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launch()
        let latest = app.descendants(matching: .any)["cachedMessage-latest"].firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 10)); latest.tap()
        XCTAssertTrue(app.descendants(matching: .any)["conversationBody-latest"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["conversationBody-earlier"].firstMatch.exists)
        let earlier = app.buttons["conversationHeader-earlier"]
        app.swipeDown()
        XCTAssertTrue(earlier.waitForExistence(timeout: 5)); earlier.tap()
        XCTAssertTrue(app.descendants(matching: .any)["conversationBody-earlier"].firstMatch.waitForExistence(timeout: 5))
        earlier.tap()
        XCTAssertFalse(app.descendants(matching: .any)["conversationBody-earlier"].firstMatch.exists)
    }
}
