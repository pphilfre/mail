import XCTest
import SwiftData
@testable import DispatchMail

@MainActor
final class MailStorageTests: XCTestCase {
    func testMailAndAttachmentsSurviveDatabaseReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let url = directory.appending(path: "mail.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountID = UUID()
        do {
            let container = try MailStorage.open(at: url)
            let context = container.mainContext
            let account = MailAccount(id: accountID, provider: .gmail, email: "me@example.com")
            account.historyID = "18446744073709551616" // Opaque strings, never lossy numeric conversions.
            let message = MailMessage(accountID: accountID, remoteID: "message-1", remoteThreadID: "thread-1",
                sender: MailAddress(name: "Alex", email: "alex@example.com"), subject: "Stored mail",
                snippet: "Cached preview", receivedAt: Date(timeIntervalSince1970: 1234))
            message.to = [MailAddress(name: "Me", email: "me@example.com")]
            message.cc = [MailAddress(name: nil, email: "cc@example.com")]
            message.folderIDs = ["INBOX", "Label_42"]
            message.isInbox = true; message.isStarred = true
            message.cachedText = Data("Offline body ☕".utf8)
            message.cachedHTML = Data("<p>Offline body</p>".utf8)
            let attachment = MailAttachment(accountID: accountID, messageID: message.id, partID: "1",
                filename: "notes.pdf", mimeType: "application/pdf", byteCount: 42)
            context.insert(account); context.insert(message); context.insert(attachment)
            context.insert(MailThread(accountID: accountID, remoteID: "thread-1", subject: message.subject, latestMessageAt: message.receivedAt))
            context.insert(MailFolder(accountID: accountID, remoteID: "Label_42", name: "Personal", kind: "label"))
            try context.save()
        }
        let reopened = try MailStorage.open(at: url)
        let repository = MailRepository(context: reopened.mainContext)
        let message = try XCTUnwrap(repository.message(accountID: accountID, remoteID: "message-1"))
        XCTAssertEqual(message.sender.displayName, "Alex")
        XCTAssertEqual(message.to.first?.email, "me@example.com")
        XCTAssertEqual(message.cc.first?.email, "cc@example.com")
        XCTAssertEqual(message.plainTextBody, "Offline body ☕")
        XCTAssertEqual(message.folderIDs, ["INBOX", "Label_42"])
        XCTAssertTrue(message.isStarred)
        XCTAssertEqual(try repository.account(id: accountID)?.historyID, "18446744073709551616")
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<MailAttachment>()).first?.filename, "notes.pdf")
    }

    func testFoundationMigrationIsIdempotentAndDoesNotResurrectDeletedDrafts() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let legacy = DraftStore(fileURL: FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString).appending(path: "drafts.json"))
        defer { try? FileManager.default.removeItem(at: legacy.fileURL.deletingLastPathComponent()) }
        let draft = LocalDraft(subject: "Legacy draft", body: "Keep me")
        try legacy.save([draft])
        try repository.migrateFoundationDrafts(from: legacy)
        try repository.migrateFoundationDrafts(from: legacy)
        XCTAssertEqual(try repository.load(), [draft])
        try repository.save([])
        try repository.migrateFoundationDrafts(from: legacy)
        XCTAssertTrue(try repository.load().isEmpty)
        XCTAssertEqual(try legacy.load(), [draft])
    }

    func testCorruptLegacyFileDoesNotMarkMigrationCompleteOrDiscardExistingDraft() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let existing = LocalDraft(subject: "Already saved")
        try repository.save([existing])
        let fileURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let corrupt = Data("broken draft file".utf8)
        try corrupt.write(to: fileURL)
        XCTAssertThrowsError(try repository.migrateFoundationDrafts(from: DraftStore(fileURL: fileURL)))
        XCTAssertEqual(try repository.load(), [existing])
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<StoreMetadata>()).isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
    }

    func testAccountRemovalPreservesOtherAccountAndUnassignedDraft() throws {
        let container = try MailStorage.open(inMemory: true)
        let context = container.mainContext
        let repository = MailRepository(context: context)
        let first = MailAccount(provider: .gmail, email: "first@example.com")
        let second = MailAccount(provider: .gmail, email: "second@example.com")
        context.insert(first); context.insert(second)
        for account in [first, second] {
            let message = MailMessage(accountID: account.id, remoteID: "same-provider-id", remoteThreadID: "thread",
                sender: MailAddress(name: nil, email: "sender@example.com"), subject: "Mail", snippet: "", receivedAt: Date())
            context.insert(message)
            context.insert(MailAttachment(accountID: account.id, messageID: message.id, partID: "0", filename: "file.txt", mimeType: "text/plain", byteCount: 10))
            context.insert(MailThread(accountID: account.id, remoteID: "thread", subject: "Mail", latestMessageAt: Date()))
            context.insert(MailFolder(accountID: account.id, remoteID: "INBOX", name: "Inbox", kind: "label"))
            context.insert(PendingMailOperation(accountID: account.id, targetRemoteID: message.remoteID, kind: "archive"))
        }
        let unassigned = OutgoingMessage(draft: LocalDraft(subject: "Unassigned"))
        let assigned = OutgoingMessage(draft: LocalDraft(subject: "Assigned"))
        assigned.accountID = first.id
        context.insert(unassigned); context.insert(assigned)
        try context.save()
        let removedID = first.id
        try repository.removeAccountData(id: removedID)
        XCTAssertNil(try repository.account(id: removedID))
        XCTAssertNotNil(try repository.account(id: second.id))
        XCTAssertNil(try repository.message(accountID: removedID, remoteID: "same-provider-id"))
        XCTAssertNotNil(try repository.message(accountID: second.id, remoteID: "same-provider-id"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailAttachment>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailThread>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MailFolder>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingMailOperation>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OutgoingMessage>()).map(\.id), [unassigned.id])
    }

    func testSwiftDataDraftEditingAndSessionRestart() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let session = AppSession(draftStore: repository)
        var draft = LocalDraft(to: "alex@example.com", cc: "cc@example.com", bcc: "bcc@example.com", subject: "Original", body: "Body")
        try session.save(draft)
        draft.subject = "Edited"
        try session.save(draft)
        XCTAssertEqual(AppSession(draftStore: repository).drafts, [draft])
        try session.deleteDraft(at: IndexSet(integer: 0))
        XCTAssertTrue(try repository.load().isEmpty)
    }
}
