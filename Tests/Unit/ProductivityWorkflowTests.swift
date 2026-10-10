import XCTest
import SwiftData
@testable import DispatchMail

@MainActor final class ProductivityWorkflowTests: XCTestCase {
    func testQueuedSendIsDurableCancellableAndExcludedFromDrafts() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        container.mainContext.insert(account); try container.mainContext.save()
        let draft = LocalDraft(to: "you@example.com", subject: "Scheduled", body: "Keep this", accountID: account.id)
        try repository.save([draft])
        let date = Date().addingTimeInterval(3600)
        let queuedRow = try XCTUnwrap(repository.outgoing(draft.id))
        queuedRow.lastError = "remote-draft-create-unconfirmed"
        XCTAssertThrowsError(try repository.schedule(draft, at: date)) { XCTAssertEqual($0 as? GmailError, .uncertainDraft) }
        XCTAssertEqual(queuedRow.stateRaw, "draft")
        queuedRow.lastError = nil
        try repository.schedule(draft, at: date)
        XCTAssertTrue(try repository.load().isEmpty)
        XCTAssertTrue(try repository.scheduledDue(at: date.addingTimeInterval(-1)).isEmpty)
        XCTAssertEqual(try repository.scheduledDue(at: date).map(\.id), [draft.id])
        try repository.deferScheduled(draft.id, until: date.addingTimeInterval(60), error: "Offline")
        XCTAssertTrue(try repository.scheduledDue(at: date).isEmpty)
        XCTAssertEqual(try repository.scheduledDue(at: date.addingTimeInterval(60)).map(\.id), [draft.id])
        try repository.cancelScheduled(draft.id)
        XCTAssertEqual(try repository.load().first?.body, "Keep this")
        XCTAssertNil(try repository.metadata(ScheduledDelivery.key(draft.id)))
        let row = try XCTUnwrap(repository.outgoing(draft.id))
        row.stateRaw = "sending"; try container.mainContext.save()
        XCTAssertThrowsError(try repository.cancelScheduled(draft.id))
    }
    func testScheduledDeliverySurvivesDatabaseReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let url = folder.appending(path: "mail.sqlite")
        defer { try? FileManager.default.removeItem(at: folder) }
        let draftID = UUID(), accountID = UUID(), due = Date().addingTimeInterval(60)
        do {
            let container = try MailStorage.open(at: url)
            let repository = MailRepository(context: container.mainContext)
            container.mainContext.insert(MailAccount(id: accountID, provider: .gmail, email: "me@example.com"))
            try container.mainContext.save()
            let draft = LocalDraft(id: draftID, to: "you@example.com", body: "Durable", accountID: accountID)
            try repository.save([draft]); try repository.schedule(draft, at: due)
        }
        let reopened = try MailStorage.open(at: url)
        let repository = MailRepository(context: reopened.mainContext)
        XCTAssertEqual(try repository.scheduledDue(at: due).map(\.id), [draftID])
        try repository.recoverInterruptedSends()
        XCTAssertEqual(try repository.outgoing(draftID)?.stateRaw, "scheduled")
        try repository.cancelScheduled(draftID)
        XCTAssertEqual(try repository.load().first?.body, "Durable")
    }

    func testRuleRunsOncePerRevisionAndAccountAndNeverTouchesSentMail() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        container.mainContext.insert(account)
        let mail = MailMessage(accountID: account.id, remoteID: "first", remoteThreadID: "first",
            sender: MailAddress(email: "news@example.com"), subject: "Daily news", snippet: "", receivedAt: Date())
        mail.isInbox = true; mail.folderIDs = ["INBOX", "UNREAD"]; container.mainContext.insert(mail)
        var rule = MailOrganisationRule(name: "News", sender: "news@example.com", accountID: account.id, action: "archive")
        try repository.saveRule(rule)
        try repository.applyRules(to: [mail]); try repository.applyRules(to: [mail]); try container.mainContext.save()
        XCTAssertFalse(mail.isInbox)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PendingMailOperation>()).count, 1)
        rule.revision = UUID(); rule.action = "star"; try repository.saveRule(rule)
        mail.isSent = true
        try repository.applyRules(to: [mail]); XCTAssertFalse(mail.isStarred)
        mail.isSent = false; try repository.applyRules(to: [mail]); XCTAssertTrue(mail.isStarred)
    }
    func testAdvancedFiltersAndLegacySavedSearchDecoding() throws {
        let filters = try JSONDecoder().decode(MailSearchFilters.self, from: Data(#"{"unread":false,"starred":false,"attachments":false}"#.utf8))
        XCTAssertFalse(filters.active)
        let account = UUID(), date = Date()
        let row = MailSearchDocument(id: UUID(), accountID: account, fields: ["budget"], sender: "alex@example.com", receivedAt: date, hasAttachments: true)
        let index = MailSearchIndex(documents: [row])
        XCTAssertEqual(index.matches("", accountID: account), [row.id])
        var advanced = MailSearchFilters(sender: "Alex", after: date, before: date.addingTimeInterval(1), attachmentPresence: true)
        XCTAssertEqual(index.matches("", filters: advanced), [row.id])
        advanced.attachmentPresence = false; XCTAssertTrue(index.matches("", filters: advanced).isEmpty)
    }
    func testUnsubscribeRejectsLocalURLsAndRequiresAdvertisedPost() {
        let privateLink = MailUnsubscribe(header: "<https://127.0.0.1/remove>, <https://host.local/remove>", post: "List-Unsubscribe=One-Click", signature: "", authentication: "")
        XCTAssertNil(privateLink.web); XCTAssertFalse(privateLink.oneClick)
        let manual = MailUnsubscribe(header: "<https://example.com/remove>, <mailto:leave@example.com>", post: "", signature: "", authentication: "")
        XCTAssertNotNil(manual.web); XCTAssertNotNil(manual.mail); XCTAssertFalse(manual.oneClick)
    }
}
