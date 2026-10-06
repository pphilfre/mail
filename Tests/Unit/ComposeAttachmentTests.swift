import Foundation
import SwiftData
import XCTest
@testable import DispatchMail

@MainActor
final class ComposeAttachmentTests: XCTestCase {
    func testFileImportCopiesOriginalAndRejectsFoldersAndSymlinkParents() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appending(path: "files"), source = base.appending(path: "original.txt")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: source)
        let store = DraftAttachmentStore(root: root)
        var draft = LocalDraft(to: "other@example.com")
        let item = try await store.importFile(source, draftID: draft.id, existing: [])
        draft.attachments = [item]
        try Data("changed".utf8).write(to: source)
        let raw = try await store.raw(draft, from: "me@example.com")
        XCTAssertTrue(try XCTUnwrap(String(data: XCTUnwrap(Base64URL.decode(raw)), encoding: .utf8)).contains(Data("original".utf8).base64EncodedString()))
        do { _ = try await store.importFile(base, draftID: draft.id, existing: []); XCTFail("Imported folder") }
        catch { XCTAssertEqual(error as? ComposeAttachmentError, .invalidFile) }
        let escapeID = UUID()
        try FileManager.default.createSymbolicLink(at: root.appending(path: escapeID.uuidString), withDestinationURL: base)
        do {
            _ = try await store.store(Data([1]), filename: "outside", mimeType: "text/plain", draftID: escapeID, existing: [])
            XCTFail("Escaped root through parent symlink")
        } catch { XCTAssertEqual(error as? ComposeAttachmentError, .invalidFile) }
    }
    func testFilesReopenWithDraftAndDiscardRestoresOriginalAttachments() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MailStorage.open(at: root.appending(path: "mail.sqlite"))
        let repository = MailRepository(context: container.mainContext)
        let session = AppSession(draftStore: repository)
        let store = DraftAttachmentStore(root: root.appending(path: "files"))
        var original = LocalDraft(subject: "Files")
        let item = try await store.store(Data([0, 1, 255, 10]), filename: "report.pdf", mimeType: "application/pdf", draftID: original.id, existing: [])
        original.attachments = [item]; try session.save(original)
        let reopened = try MailStorage.open(at: root.appending(path: "mail.sqlite"))
        XCTAssertEqual(try MailRepository(context: reopened.mainContext).load().first?.attachments, [item])
        let file = try await DraftAttachmentStore(root: root.appending(path: "files")).preview(item, draftID: original.id)
        XCTAssertEqual(try Data(contentsOf: file), Data([0, 1, 255, 10]))
        let editor = DraftEditingSession(draft: original, alreadySaved: true)
        var edited = original; edited.attachments = []
        try editor.checkpoint(edited, session: session)
        XCTAssertTrue(try repository.load()[0].attachments.isEmpty)
        try editor.discard(session: session)
        XCTAssertEqual(try repository.load()[0].attachments, [item])
        try session.deleteDraft(id: original.id)
        XCTAssertNil(try repository.metadata(DraftAttachments.key(original.id)))
    }

    func testLegacyDraftJSONAndAttachmentOnlyDraftRemainCompatible() throws {
        let original = LocalDraft(subject: "Legacy")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "attachments")
        let restored = try JSONDecoder().decode(LocalDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, original)
        var onlyFile = LocalDraft()
        onlyFile.attachments = [DraftAttachment(id: UUID(), filename: "empty.txt", mimeType: "text/plain", byteCount: 0, sha256: "")]
        XCTAssertFalse(onlyFile.isEmpty)
        XCTAssertThrowsError(try MailMIME.raw(onlyFile, from: "me@example.com"))
    }

    func testMultipartContainsExactBinaryBytesUnicodeFilenameAndSafeHeaders() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DraftAttachmentStore(root: root)
        var draft = LocalDraft(to: "other@example.com", body: "Hello\nWorld", inReplyTo: "<original@example.com>")
        let bytes = Data([0, 13, 10, 255, 128, 42])
        let item = try await store.store(bytes, filename: "résumé.pdf", mimeType: "application/pdf\r\nBcc: injected@example.com", draftID: draft.id, existing: [])
        draft.attachments = [item]
        let raw = try await store.raw(draft, from: "me@example.com")
        let mime = try XCTUnwrap(String(data: XCTUnwrap(Base64URL.decode(raw)), encoding: .utf8))
        XCTAssertTrue(mime.contains("Content-Type: multipart/mixed; boundary="))
        XCTAssertTrue(mime.contains("Content-Type: application/octet-stream"))
        XCTAssertFalse(mime.contains("injected@example.com"))
        XCTAssertTrue(mime.contains(bytes.base64EncodedString()))
        XCTAssertTrue(mime.contains(Data("Hello\r\nWorld".utf8).base64EncodedString()))
        XCTAssertTrue(mime.contains("filename*0*=UTF-8''%72%C3%A9%73%75%6D%C3%A9%2E%70%64%66"))
        XCTAssertTrue(mime.contains("In-Reply-To: <original@example.com>"))
        XCTAssertTrue(mime.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count < 998 })
        // An independent RFC MIME parser in CI validates bytes and decoded filenames.
        let fixture = URL.applicationSupportDirectory.appending(path: "Dispatch/compose-mime-fixture.eml")
        try FileManager.default.createDirectory(at: fixture.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(mime.utf8).write(to: fixture, options: .atomic)
    }

    func testSizeCountCorruptionAndMissingFilesCannotBeSent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DraftAttachmentStore(root: root)
        var draft = LocalDraft(to: "other@example.com")
        let item = try await store.store(Data("original".utf8), filename: "../../file.txt", mimeType: "text/plain", draftID: draft.id, existing: [])
        XCTAssertFalse(item.filename.contains("/"))
        draft.attachments = [item]
        let file = try await store.preview(item, draftID: draft.id)
        try Data("modified".utf8).write(to: file)
        do { _ = try await store.raw(draft, from: "me@example.com"); XCTFail("Changed file sent") }
        catch { XCTAssertEqual(error as? ComposeAttachmentError, .unavailable) }
        try FileManager.default.removeItem(at: file)
        do { _ = try await store.raw(draft, from: "me@example.com"); XCTFail("Missing file sent") }
        catch { XCTAssertEqual(error as? ComposeAttachmentError, .unavailable) }
        let big = DraftAttachment(id: UUID(), filename: "big", mimeType: "text/plain", byteCount: DraftAttachmentStore.maximumBytes, sha256: "")
        let small = DraftAttachment(id: UUID(), filename: "small", mimeType: "text/plain", byteCount: 1, sha256: "")
        XCTAssertThrowsError(try DraftAttachmentStore.validate([big, small]))
        let many = (0...20).map { _ in DraftAttachment(id: UUID(), filename: "empty", mimeType: "text/plain", byteCount: 0, sha256: "") }
        XCTAssertThrowsError(try DraftAttachmentStore.validate(many))
        XCTAssertThrowsError(try DraftAttachmentStore.validate([small, small]))
    }

    func testOwnedDraftRevisionCannotBeReplacedByMailboxRefreshOrAccountSwitch() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        let draft = LocalDraft(to: "other@example.com", accountID: account.id)
        try repository.save([draft])
        let row = try XCTUnwrap(repository.outgoing(draft.id))
        let owned = GmailDraftDTO(id: "remote", message: GmailMessageDTO(id: "written", threadId: "thread", payload: GmailPart(mimeType: "multipart/mixed")))
        try repository.acknowledgeDraft(owned, row: row)
        XCTAssertTrue(try repository.canReplaceDraft(owned, row: row))
        let changed = GmailDraftDTO(id: "remote", message: GmailMessageDTO(id: "changed", threadId: "thread", payload: GmailPart(mimeType: "text/plain")))
        try repository.replaceDraftLinks([changed], accountID: account.id)
        XCTAssertFalse(try repository.canReplaceDraft(changed, row: row))
        var moved = draft; moved.accountID = UUID()
        try repository.save([moved])
        XCTAssertNil(try repository.metadata(DraftAttachments.revisionKey(draft.id)))
        XCTAssertNil(row.remoteDraftID)
    }

    func testAttachmentDraftUploadsAgainButExternalChangeIsNeverOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DraftAttachmentStore(root: root)
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        var draft = LocalDraft(to: "other@example.com", accountID: account.id)
        let item = try await store.store(Data("File".utf8), filename: "notes.txt", mimeType: "text/plain", draftID: draft.id, existing: [])
        draft.attachments = [item]; try repository.save([draft])
        let vault = CredentialVault(service: "dispatch.compose.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let replies = [#"{"drafts":[]}"#, #"{"id":"draft","message":{"id":"one","threadId":"thread"}}"#,
            #"{"id":"draft","message":{"id":"one","threadId":"thread","payload":{"mimeType":"multipart/mixed"}}}"#,
            #"{"id":"draft","message":{"id":"two","threadId":"thread"}}"#,
            #"{"id":"draft","message":{"id":"external","threadId":"thread","payload":{"mimeType":"text/plain"}}}"#]
        let transport = FixtureTransport(replies.map { HTTPReply(data: Data($0.utf8), status: 200) })
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport, draftAttachments: store)
        try await coordinator.saveRemoteDraft(draft)
        draft.body = "Updated"; try repository.save([draft])
        try await coordinator.saveRemoteDraft(draft)
        do { try await coordinator.saveRemoteDraft(draft); XCTFail("Overwrote external draft") }
        catch { XCTAssertEqual(error as? GmailError, .unsupportedDraft) }
        let requests = await transport.captured()
        let uploads = requests.filter { $0.httpMethod == "POST" || $0.httpMethod == "PUT" }
        XCTAssertEqual(uploads.count, 2)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(uploads[0].httpBody)) as? [String: Any])
        let message = try XCTUnwrap(json["message"] as? [String: Any])
        let raw = try XCTUnwrap(message["raw"] as? String)
        XCTAssertTrue(try XCTUnwrap(String(data: XCTUnwrap(Base64URL.decode(raw)), encoding: .utf8)).contains("multipart/mixed"))
        try await vault.remove(for: account.id)
    }
}
