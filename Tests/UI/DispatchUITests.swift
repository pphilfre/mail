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

    func testAttachmentLibrarySearchAndSourceConversation() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_LIBRARY"] = "YES"
        app.launch()
        app.buttons["profileMenuButton"].tap(); app.buttons["openAttachmentsButton"].tap()
        let file = app.descendants(matching: .any)["libraryFile-Project plans.pdf"].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Inline logo.png"].exists)
        attachScreenshot("Attachment library", app: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Project")
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        let source = app.descendants(matching: .any)["attachmentSource-Project plans.pdf"].firstMatch
        XCTAssertTrue(source.exists); source.tap()
        XCTAssertTrue(app.descendants(matching: .any)["conversationBody-latest"].firstMatch.waitForExistence(timeout: 5))
    }

    func testPeopleProfileCanSaveNicknameAndShowSenderFiles() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_LIBRARY"] = "YES"
        app.launch()
        app.buttons["profileMenuButton"].tap(); app.buttons["openPeopleButton"].tap()
        let person = app.descendants(matching: .any)["senderProfile-reader-fixture@gmail.com"].firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 10)); person.tap()
        XCTAssertTrue(app.staticTexts["Received"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["senderActivityChart"].firstMatch.exists)
        let edit = app.buttons["editSenderProfileButton"]
        if !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let nickname = app.textFields["senderNicknameField"]
        XCTAssertTrue(nickname.waitForExistence(timeout: 5)); nickname.tap(); nickname.typeText("Alex")
        let notes = app.textViews["senderNotesField"]
        notes.tap(); notes.typeText("Prefers email after lunch")
        app.buttons["saveSenderProfileButton"].tap()
        XCTAssertTrue(app.staticTexts["Prefers email after lunch"].waitForExistence(timeout: 5))
        let tabs = app.segmentedControls["senderContentPicker"]
        if !tabs.isHittable { app.swipeUp() }
        tabs.buttons["Files"].tap()
        XCTAssertTrue(app.staticTexts["Project plans.pdf"].waitForExistence(timeout: 5))
        attachScreenshot("Sender profile with files", app: app)
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["Alex"].waitForExistence(timeout: 5))
    }

    func testConversationOpensSenderProfile() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launch()
        let latest = app.descendants(matching: .any)["cachedMessage-latest"].firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 10)); latest.tap()
        let profile = app.buttons["openSenderProfile-latest"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5)); profile.tap()
        XCTAssertTrue(app.navigationBars["Sender profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reader-fixture@gmail.com"].exists)
    }

    func testCollectionCreatedFromReaderIncludesThreadFilesAndCanRemoveMembership() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_LIBRARY"] = "YES"
        app.launch()
        let latest = app.descendants(matching: .any)["cachedMessage-latest"].firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 10)); latest.tap()
        app.buttons["More"].tap(); app.buttons["addToCollectionButton"].tap()
        app.buttons["New collection"].tap()
        let name = app.textFields["collectionNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("House move")
        app.buttons["saveCollectionButton"].tap()
        XCTAssertTrue(app.buttons["House move"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["profileMenuButton"].tap(); app.buttons["openCollectionsButton"].tap()
        let collection = app.descendants(matching: .any)["collection-House move"].firstMatch
        XCTAssertTrue(collection.waitForExistence(timeout: 5)); collection.tap()
        app.segmentedControls["collectionContentPicker"].buttons["Files"].tap()
        XCTAssertTrue(app.staticTexts["Project plans.pdf"].waitForExistence(timeout: 5))
        attachScreenshot("Project collection files", app: app)
        app.buttons["addCollectionMailButton"].tap()
        let member = app.buttons["collectionMember-latest"]
        XCTAssertTrue(member.waitForExistence(timeout: 5)); XCTAssertEqual(member.value as? String, "Included")
        member.tap(); XCTAssertEqual(member.value as? String, "Not included")
        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["Project plans.pdf"].exists)
        XCTAssertTrue(app.staticTexts["No files in these downloaded conversations."].exists)
    }

    func testSubscriptionsDetectSenderAndManualExclusionCanBeReversed() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_SUBSCRIPTIONS"] = "YES"
        app.launch()
        app.buttons["profileMenuButton"].tap(); app.buttons["openSubscriptionsButton"].tap()
        let newsletter = app.descendants(matching: .any)["subscription-news@example.com"].firstMatch
        XCTAssertTrue(newsletter.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 unread · 1 message · 1 in 7 days"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["subscription-reader-fixture@gmail.com"].firstMatch.exists)
        attachScreenshot("Subscription centre", app: app)
        app.buttons["manageSubscriptionsButton"].tap()
        let exclude = app.buttons["excludeSubscription-news@example.com"]
        XCTAssertTrue(exclude.waitForExistence(timeout: 5)); exclude.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["No newsletters here"].waitForExistence(timeout: 5))
        app.buttons["manageSubscriptionsButton"].tap()
        let include = app.buttons["includeSubscription-news@example.com"]
        XCTAssertTrue(include.waitForExistence(timeout: 5)); include.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(newsletter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Added by you"].exists)
    }

    func testSubscriptionArchiveConfirmsCountAndCanUndoWithoutAProvider() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_SUBSCRIPTIONS"] = "YES"
        app.launch()
        app.buttons["profileMenuButton"].tap(); app.buttons["openSubscriptionsButton"].tap()
        let archive = app.buttons["archiveSubscription-news@example.com"]
        XCTAssertTrue(archive.waitForExistence(timeout: 10)); archive.tap()
        let confirm = app.buttons["Archive 1 inbox message"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(archive.waitForExistence(timeout: 5)); XCTAssertFalse(archive.isEnabled)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["cachedMessage-newsletter-fixture"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["cachedMessage-latest"].firstMatch.exists)
        let undo = app.buttons["triageUndo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cachedMessage-newsletter-fixture"].firstMatch.waitForExistence(timeout: 5))
    }

    func testMailTaskCanBeCreatedCompletedAndReopenedWithConversationLink() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launch()
        let message = app.descendants(matching: .any)["cachedMessage-latest"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10)); message.tap()
        app.buttons["More"].tap(); app.buttons["makeMailTaskButton"].tap()
        let title = app.textFields["mailTaskTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let notes = app.textViews["mailTaskNotes"]
        notes.tap(); notes.typeText("Check the delivery date")
        app.switches["mailTaskDueToggle"].tap()
        app.buttons["saveMailTaskButton"].tap()
        XCTAssertTrue(app.staticTexts["Task saved"].waitForExistence(timeout: 5))
        let closeFeedback = app.buttons["Dismiss confirmation"]
        if closeFeedback.exists { closeFeedback.tap() }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["profileMenuButton"].tap(); app.buttons["openTasksButton"].tap()
        let toggle = app.buttons["toggleTask-latest"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Check the delivery date"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["taskConversation-latest"].firstMatch.exists)
        attachScreenshot("Tasks with a linked conversation", app: app)
        toggle.tap()
        XCTAssertFalse(toggle.exists)
        app.segmentedControls["taskStatusFilter"].buttons["Completed"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
        app.segmentedControls["taskStatusFilter"].buttons["Open"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }

    func testReceiptIsDetectedAndCanBeReviewedWithoutProviderAccess() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_READER"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_PRODUCTIVITY"] = "YES"
        app.launch()
        app.buttons["profileMenuButton"].tap(); app.buttons["openReceiptsButton"].tap()
        let receipt = app.descendants(matching: .any)["receipt-receipt-fixture"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["GBP 22.00"].exists)
        attachScreenshot("Local receipt organiser", app: app)
        receipt.tap()
        app.buttons["reviewReceiptButton"].tap()
        let merchant = app.textFields["receiptMerchant"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5))
        merchant.tap(); merchant.typeText(" Shop")
        app.buttons["saveReceiptButton"].tap()
        XCTAssertTrue(app.staticTexts["Receipt saved"].waitForExistence(timeout: 5))
        let closeFeedback = app.buttons["Dismiss confirmation"]
        if closeFeedback.exists { closeFeedback.tap() }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Paper & Ink Shop"].waitForExistence(timeout: 5))
    }

    func testAttachedDraftReopensAndRemovalPersistsAfterRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["DISPATCH_UI_TEST_SAMPLE_INBOX"] = "YES"
        app.launchEnvironment["DISPATCH_UI_TEST_DRAFT_ATTACHMENT"] = "YES"
        app.launch()
        app.descendants(matching: .any)["draftsShortcut"].tap()
        let draft = app.staticTexts["Attachment test draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10)); draft.tap()
        let remove = app.buttons["removeAttachment-fixture.txt"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["attachFileButton"].exists)
        XCTAssertTrue(app.buttons["attachPhotoButton"].exists)
        attachScreenshot("Composer with persisted attachment", app: app)
        remove.tap()
        app.buttons["saveDraftButton"].tap()
        app.terminate(); app.launch()
        app.descendants(matching: .any)["draftsShortcut"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap()
        XCTAssertFalse(app.buttons["removeAttachment-fixture.txt"].exists)
        XCTAssertEqual(app.textViews["composeBody"].value as? String, "Keep this body")
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
