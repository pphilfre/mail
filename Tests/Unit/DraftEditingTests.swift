import XCTest
@testable import DispatchMail

@MainActor
final class DraftEditingTests: XCTestCase {
    func testNewDraftCheckpointsAndDiscardRemovesOnlyThatDraft() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let session = AppSession(draftStore: repository)
        let unrelated = LocalDraft(subject: "Another draft")
        try session.save(unrelated)
        var draft = LocalDraft()
        let editor = DraftEditingSession(draft: draft, alreadySaved: false)
        draft.subject = "Auto saved"; draft.body = "Keep my typing"
        try editor.checkpoint(draft, session: session)
        XCTAssertTrue(editor.saved)
        XCTAssertEqual(AppSession(draftStore: repository).drafts.first { $0.id == draft.id }?.body, draft.body)
        try editor.discard(session: session)
        XCTAssertEqual(try repository.load(), [unrelated])
    }

    func testDiscardEditedDraftRestoresOriginalIncludingRecipients() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let session = AppSession(draftStore: repository)
        let original = LocalDraft(to: "a@example.com", cc: "cc@example.com", subject: "Original", body: "Original body")
        try session.save(original)
        let editor = DraftEditingSession(draft: original, alreadySaved: true)
        var edited = original; edited.subject = "Edited"; edited.to = "b@example.com"
        try editor.checkpoint(edited, session: session)
        XCTAssertEqual(try repository.load().first?.to, edited.to)
        try editor.discard(session: session)
        XCTAssertEqual(try repository.load(), [original])
    }

    func testEmptyDraftDoesNotPersistAndClearingAutosavedDraftRemovesIt() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let session = AppSession(draftStore: repository)
        var draft = LocalDraft()
        let editor = DraftEditingSession(draft: draft, alreadySaved: false)
        try editor.checkpoint(draft, session: session)
        XCTAssertTrue(try repository.load().isEmpty)
        draft.subject = "Typing"; try editor.checkpoint(draft, session: session)
        draft.subject = ""; try editor.checkpoint(draft, session: session)
        XCTAssertTrue(try repository.load().isEmpty)
        XCTAssertFalse(editor.saved)
    }

    func testStaleSessionPreservesProviderImportedDraftAndSentState() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let session = AppSession(draftStore: repository)
        let original = LocalDraft(subject: "Open editor")
        try session.save(original)
        let imported = LocalDraft(subject: "Provider import")
        try repository.save([original, imported])
        var edited = original; edited.body = "Changed"
        let editor = DraftEditingSession(draft: original, alreadySaved: true)
        try editor.checkpoint(edited, session: session)
        XCTAssertNotNil(try repository.outgoing(imported.id))
        let sent = try XCTUnwrap(repository.outgoing(original.id))
        sent.stateRaw = "sent"; try repository.context.save()
        edited.body = "More typing"
        XCTAssertThrowsError(try editor.checkpoint(edited, session: session))
        XCTAssertEqual(sent.stateRaw, "sent")
        XCTAssertNotNil(try repository.outgoing(imported.id))
    }

    func testRichAndExternalDraftBodiesCannotBeOverwritten() {
        let plain = GmailPart(mimeType: "text/plain", body: GmailBody(data: Base64URL.encode(Data("Body".utf8))))
        let html = GmailPart(mimeType: "text/html", body: GmailBody(data: Base64URL.encode(Data("<b>Body</b>".utf8))))
        let file = GmailPart(mimeType: "application/pdf", filename: "notes.pdf", body: GmailBody(attachmentId: "file"))
        XCTAssertTrue(MailMIME.canEditDraft(plain))
        XCTAssertFalse(MailMIME.canEditDraft(html))
        XCTAssertFalse(MailMIME.canEditDraft(GmailPart(mimeType: "multipart/alternative", parts: [plain, html])))
        XCTAssertFalse(MailMIME.canEditDraft(GmailPart(mimeType: "multipart/mixed", parts: [plain, file])))
        XCTAssertFalse(MailMIME.canEditDraft(GmailPart(mimeType: "text/plain", body: GmailBody(attachmentId: "external"))))
    }
}
