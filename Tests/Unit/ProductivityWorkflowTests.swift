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
        try repository.schedule(draft, at: date)
        XCTAssertTrue(try repository.load().isEmpty)
        XCTAssertTrue(try repository.scheduledDue(at: date.addingTimeInterval(-1)).isEmpty)
        XCTAssertEqual(try repository.scheduledDue(at: date).map(\.id), [draft.id])
        try repository.cancelScheduled(draft.id)
        XCTAssertEqual(try repository.load().first?.body, "Keep this")
        XCTAssertNil(try repository.metadata(ScheduledDelivery.key(draft.id)))
        let row = try XCTUnwrap(repository.outgoing(draft.id))
        row.stateRaw = "sending"; try container.mainContext.save()
        XCTAssertThrowsError(try repository.cancelScheduled(draft.id))
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
