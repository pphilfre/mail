import XCTest
import SwiftData
@testable import DispatchMail

@MainActor
final class MailFeatureTests: XCTestCase {
    private func message(_ repository: MailRepository, _ account: MailAccount, id: String, labels: [String], date: Double = 1) -> MailMessage {
        let row = MailMessage(accountID: account.id, remoteID: id, remoteThreadID: "shared-thread",
            sender: MailAddress(name: nil, email: "alex@example.com"), subject: "Subject", snippet: id,
            receivedAt: Date(timeIntervalSince1970: date))
        row.folderIDs = labels; MailRepository.flags(row); repository.context.insert(row)
        return row
    }
    func testConversationGroupingKeepsAccountsAndEmptyThreadIDsSeparate() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let first = MailAccount(provider: .gmail, email: "first@example.com")
        let second = MailAccount(provider: .gmail, email: "second@example.com")
        repository.context.insert(first); repository.context.insert(second)
        let older = message(repository, first, id: "old", labels: ["INBOX", "UNREAD"], date: 1)
        let latest = message(repository, first, id: "new", labels: ["INBOX"], date: 3)
        let other = message(repository, second, id: "other", labels: ["INBOX"], date: 2)
        let rows = MailConversation.rows([older, other, latest], grouped: true)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].latest.id, latest.id)
        XCTAssertFalse(rows[0].isRead)
        XCTAssertEqual(rows[0].messages.count, 2)
        XCTAssertEqual(MailConversation.rows([older, other, latest], grouped: false).count, 3)
        older.remoteThreadID = ""; latest.remoteThreadID = ""
        XCTAssertEqual(MailConversation.rows([older, latest], grouped: true).count, 2)
    }
    func testBulkUndoPreservesUnrelatedLabelsAndQueuesInOrderAcrossAccounts() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let first = MailAccount(provider: .gmail, email: "first@example.com")
        let second = MailAccount(provider: .gmail, email: "second@example.com")
        repository.context.insert(first); repository.context.insert(second)
        let inbox = message(repository, first, id: "in", labels: ["INBOX", "UNREAD"])
        let archived = message(repository, second, id: "out", labels: ["STARRED"])
        try repository.context.save()
        let now = Date()
        let record = try XCTUnwrap(repository.enqueueBatch("trash", messages: [inbox, archived, inbox], now: now))
        XCTAssertEqual(record.count, 2)
        XCTAssertTrue(inbox.isTrash); XCTAssertFalse(inbox.isInbox)
        MailRepository.overlay("labelAdd:Label_new", on: inbox)
        let ids = try repository.undoTriage(record.id, now: now.addingTimeInterval(1))
        XCTAssertEqual(ids, [first.id, second.id])
        XCTAssertFalse(inbox.isTrash); XCTAssertTrue(inbox.isInbox)
        XCTAssertTrue(inbox.folderIDs.contains("Label_new"))
        XCTAssertFalse(archived.isTrash); XCTAssertFalse(archived.isInbox)
        let queued = try repository.context.fetch(FetchDescriptor<PendingMailOperation>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(queued.map(\.kindRaw), ["trash", "trash", "restore", "labelAdd:INBOX", "restore"])
        XCTAssertTrue(try repository.undoTriage(record.id).isEmpty)
    }
    func testUndoAfterAcknowledgementAndExpiry() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        let row = message(repository, account, id: "mail", labels: ["INBOX", "UNREAD"])
        try repository.context.save()
        let now = Date()
        let record = try XCTUnwrap(repository.enqueueBatch("archive", messages: [row], now: now))
        // Simulate acknowledgement: originals no longer exist in the queue.
        try repository.context.delete(model: PendingMailOperation.self)
        try repository.context.save()
        _ = try repository.undoTriage(record.id, now: now.addingTimeInterval(2))
        XCTAssertTrue(row.isInbox); XCTAssertFalse(row.isRead)
        let expired = try XCTUnwrap(repository.enqueueBatch("archive", messages: [row], now: now))
        XCTAssertTrue(try repository.undoTriage(expired.id, now: now.addingTimeInterval(11)).isEmpty)
        XCTAssertFalse(row.isInbox)
    }
    func testSpamUndoAndCachedMailboxScope() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        let row = message(repository, account, id: "mail", labels: ["INBOX", "UNREAD", "SENT"])
        try repository.context.save()
        let record = try XCTUnwrap(repository.enqueueBatch("spam", messages: [row]))
        XCTAssertTrue(MailboxScope.contains(row, mailbox: "Spam"))
        XCTAssertFalse(MailboxScope.contains(row, mailbox: "Sent"))
        XCTAssertFalse(MailboxScope.contains(row, mailbox: "Unread"))
        _ = try repository.undoTriage(record.id)
        XCTAssertTrue(row.isInbox); XCTAssertFalse(row.isSpam)
    }
    func testUndoSurvivesReopenAndAccountRemovalClearsIt() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "mail.sqlite")
        let accountID = UUID(); var undoID: UUID!
        do {
            let container = try MailStorage.open(at: url)
            let repository = MailRepository(context: container.mainContext)
            let account = MailAccount(id: accountID, provider: .gmail, email: "me@example.com")
            repository.context.insert(account)
            let row = message(repository, account, id: "mail", labels: ["INBOX"])
            try repository.context.save()
            undoID = try XCTUnwrap(repository.enqueueBatch("archive", messages: [row])).id
        }
        let container = try MailStorage.open(at: url)
        let repository = MailRepository(context: container.mainContext)
        _ = try repository.undoTriage(undoID)
        let row = try XCTUnwrap(repository.message(accountID: accountID, remoteID: "mail"))
        XCTAssertTrue(row.isInbox)
        _ = try repository.enqueueBatch("trash", messages: [row])
        try repository.removeAccountData(id: accountID)
        XCTAssertFalse(try repository.context.fetch(FetchDescriptor<StoreMetadata>()).contains { $0.key == MailUndoRecord.key })
    }
    func testRejectedOperationDoesNotBlockOtherMessagesAndPreservesTargetOrder() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        let first = message(repository, account, id: "first", labels: ["INBOX", "UNREAD"])
        let second = message(repository, account, id: "second", labels: ["INBOX", "UNREAD"])
        try repository.context.save()
        try repository.enqueue("read", message: first)
        try repository.enqueue("star", message: first)
        try repository.enqueue("read", message: second)
        let transport = FixtureTransport([HTTPReply(data: Data("{}".utf8), status: 400), HTTPReply(data: Data("{}".utf8), status: 200)])
        let coordinator = GmailCoordinator(repository: repository, transport: transport)
        let api = GmailAPI(transport: transport) { _ in "fixture" }
        try await coordinator.flush(account.id, api: api)
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[1].url?.path.contains("second") == true)
        let queued = try repository.context.fetch(FetchDescriptor<PendingMailOperation>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(queued.count, 2)
        XCTAssertEqual(queued.first?.nextAttemptAt, .distantFuture)
        XCTAssertEqual(queued.last?.kindRaw, "star")
    }
}

final class RecipientAndSignatureTests: XCTestCase {
    func testRecipientValidationRetainsBadInputAndDetectsDuplicatesAcrossFields() {
        XCTAssertEqual(RecipientInput.tokens(#""Doe, Jane" <jane@example.com>; alex@example.com"#).count, 2)
        XCTAssertTrue(RecipientInput.invalid(#""Doe, Jane" <jane@example.com>"#).isEmpty)
        XCTAssertEqual(RecipientInput.invalid("bad, valid@example.com"), ["bad"])
        XCTAssertNil(RecipientInput.address("Jane <jane@example.com> trailing"))
        XCTAssertNil(RecipientInput.address("Jane <jane@example.com"))
        XCTAssertNil(RecipientInput.address("jane@example.com\nBcc: other@example.com"))
        XCTAssertEqual(RecipientInput.duplicateEmails(["Jane <JANE@example.com>", "", "jane@example.com"]), ["jane@example.com"])
    }
    func testAutocompletePreservesOtherRecipientsAndEscapesDisplayNames() {
        let address = MailAddress(name: "Doe, Jane", email: "jane@example.com")
        XCTAssertEqual(RecipientInput.replacingLastToken("alex@example.com, ja", with: address), #"alex@example.com, "Doe, Jane" <jane@example.com>, "#)
        XCTAssertEqual(RecipientInput.replacingLastToken("alex@example.com, ", with: address), #"alex@example.com, "Doe, Jane" <jane@example.com>, "#)
        XCTAssertTrue(RecipientInput.invalid(RecipientInput.formatted(address)).isEmpty)
        XCTAssertTrue(RecipientInput.invalid(RecipientInput.formatted(MailAddress(name: #"<Admin> \ "name""#, email: "admin@example.com"))).isEmpty)
    }
    func testSignatureReplacementDoesNotDuplicateOrOverwriteEditsAndKeepsQuotesBelowIt() {
        let reply = "\n\nOn Monday, Alex wrote:\n> earlier"
        let body = MailSignature.insert("Freddie", in: reply)
        XCTAssertEqual(MailSignature.replace("Freddie", with: "Work", in: body), MailSignature.insert("Work", in: reply))
        XCTAssertNil(MailSignature.replace("Freddie", with: "Work", in: body.replacingOccurrences(of: "Freddie", with: "Edited")))
        let plain = MailSignature.insert("Freddie", in: "Hello")
        XCTAssertEqual(MailSignature.replace("Freddie", with: "", in: plain), "Hello")
        XCTAssertTrue(MailSignature.mentionsAttachment("Please see the attached file."))
        XCTAssertFalse(MailSignature.mentionsAttachment("Thanks\n\nOn Monday, Alex wrote:\n> attached file"))
        XCTAssertFalse(MailSignature.mentionsAttachment(MailSignature.insert("Attachments team", in: "Thanks")))
    }
}
