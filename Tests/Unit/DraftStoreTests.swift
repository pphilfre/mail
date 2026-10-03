import XCTest
@testable import MailApp

@MainActor
final class DraftStoreTests: XCTestCase {
    private func makeStore() -> DraftStore {
        DraftStore(fileURL: FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "drafts.json"))
    }

    func testDraftSurvivesSessionRestartWithAllRecipients() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let draft = LocalDraft(to: "alex@example.com", cc: "team@example.com", bcc: "me@example.com",
            subject: "Café ☕", body: "First line\nSecond line")
        try AppSession(draftStore: store).save(draft)
        let restarted = AppSession(draftStore: store)
        XCTAssertEqual(restarted.drafts, [draft])
        XCTAssertNil(restarted.storageError)
    }

    func testEditingDoesNotDuplicateDraftAndDeletionPersists() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let session = AppSession(draftStore: store)
        var draft = LocalDraft(subject: "Original")
        try session.save(draft)
        draft.subject = "Updated"
        try session.save(draft)
        XCTAssertEqual(try store.load(), [draft])
        try session.deleteDraft(at: IndexSet(integer: 0))
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testCorruptStoreIsPreservedWhenSavingIsAttempted() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("not valid JSON".utf8)
        try original.write(to: store.fileURL)
        let session = AppSession(draftStore: store)
        XCTAssertNotNil(session.storageError)
        XCTAssertThrowsError(try session.save(LocalDraft(subject: "New")))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    func testFailedWriteDoesNotUpdateVisibleDrafts() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "blocker")
        try Data().write(to: blocker)
        let session = AppSession(draftStore: DraftStore(fileURL: blocker.appending(path: "drafts.json")))
        XCTAssertThrowsError(try session.save(LocalDraft(subject: "Cannot save")))
        XCTAssertTrue(session.drafts.isEmpty)
    }
}
