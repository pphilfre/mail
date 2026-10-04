import Foundation
import SwiftData
import XCTest
@testable import DispatchMail

@MainActor
final class AttachmentAndDraftCatalogTests: XCTestCase {
    func testProtectedCacheReopensOfflineAndCannotEscapeItsRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = UUID(), attachment = UUID()
        let cache = AttachmentCache(root: root)
        let bytes = Data("Saved file".utf8)
        let path = try await cache.store(bytes, accountID: account, attachmentID: attachment, filename: "../../notes.pdf")
        XCTAssertTrue(path.hasPrefix(account.uuidString + "/" + attachment.uuidString + "/"))
        let reopened = AttachmentCache(root: root)
        let file = try await reopened.existing(path)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(file)), bytes)
        do { _ = try await reopened.existing("../private.txt"); XCTFail("Path traversal") }
        catch { XCTAssertEqual(error as? AttachmentError, .invalidPath) }
        try await reopened.removeAccount(account)
        let removed = try await reopened.existing(path)
        XCTAssertNil(removed)
    }

    func testCacheSizeLimitAndAccountIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AttachmentCache(root: root), first = UUID(), second = UUID()
        let firstPath = try await cache.store(Data(), accountID: first, attachmentID: UUID(), filename: "empty.txt")
        let secondPath = try await cache.store(Data([1]), accountID: second, attachmentID: UUID(), filename: "second.txt")
        do {
            _ = try await cache.store(Data(count: AttachmentCache.maximumBytes + 1), accountID: second, attachmentID: UUID(), filename: "large")
            XCTFail("Oversized data")
        } catch { XCTAssertEqual(error as? AttachmentError, .tooLarge) }
        try await cache.removeAccount(first)
        let missing = try await cache.existing(firstPath), retained = try await cache.existing(secondPath)
        XCTAssertNil(missing); XCTAssertNotNil(retained)
    }

    func testSyncPreservesDownloadedAttachmentButInvalidatesChangedPart() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        var dto = GmailMessageDTO(id: "m", threadId: "t", payload: GmailPart(partId: "1", mimeType: "application/pdf", filename: "notes.pdf",
            body: GmailBody(attachmentId: "blob1", size: 5)))
        try repository.apply([dto], accountID: account.id)
        let first = try XCTUnwrap(repository.context.fetch(FetchDescriptor<MailAttachment>()).first)
        let firstID = first.id
        first.cachedRelativePath = "saved/notes.pdf"; try repository.context.save()
        try repository.apply([dto], accountID: account.id)
        let unchanged = try XCTUnwrap(repository.context.fetch(FetchDescriptor<MailAttachment>()).first)
        XCTAssertEqual(unchanged.id, firstID); XCTAssertEqual(unchanged.cachedRelativePath, "saved/notes.pdf")
        dto.payload?.body?.attachmentId = "blob2"
        try repository.apply([dto], accountID: account.id)
        let changed = try XCTUnwrap(repository.context.fetch(FetchDescriptor<MailAttachment>()).first)
        XCTAssertNotEqual(changed.id, firstID); XCTAssertNil(changed.cachedRelativePath)
    }

    func testDownloadReusesFileAfterSyncWithoutASecondNetworkRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        let dto = GmailMessageDTO(id: "m", threadId: "t", payload: GmailPart(partId: "1", mimeType: "application/pdf", filename: "notes.pdf",
            body: GmailBody(attachmentId: "blob", size: 5)))
        try repository.apply([dto], accountID: account.id)
        let vault = CredentialVault(service: "dispatch.attachment.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600),
            grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let transport = FixtureTransport([HTTPReply(data: Data(#"{"size":5,"data":"aGVsbG8"}"#.utf8), status: 200)])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport, attachmentCache: AttachmentCache(root: root))
        let attachment = try XCTUnwrap(repository.context.fetch(FetchDescriptor<MailAttachment>()).first)
        let file = try await coordinator.download(attachment)
        XCTAssertEqual(try Data(contentsOf: file), Data("hello".utf8))
        try repository.apply([dto], accountID: account.id)
        let reopened = GmailCoordinator(repository: repository, vault: vault, transport: transport, attachmentCache: AttachmentCache(root: root))
        let offline = try await reopened.download(attachment)
        XCTAssertEqual(offline, file)
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertTrue(requests[0].url!.path.hasSuffix("/messages/m/attachments/blob"))
        try await vault.remove(for: account.id)
    }

    func testOversizedAttachmentResponseIsRejectedBeforeBase64Decoding() async throws {
        let transport = FixtureTransport([HTTPReply(data: Data("{\"size\":\(AttachmentCache.maximumBytes + 1),\"data\":\"aA\"}".utf8), status: 200)])
        let api = GmailAPI(transport: transport) { _ in "token" }
        do { _ = try await api.attachment(messageID: "m", attachmentID: "blob"); XCTFail("Oversized response") }
        catch { XCTAssertEqual(error as? AttachmentError, .tooLarge) }
    }

    func testDraftDeduplicationUsesProviderIdentityAndNeverSubject() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let first = MailAccount(provider: .gmail, email: "first@example.com")
        let second = MailAccount(provider: .gmail, email: "second@example.com")
        repository.context.insert(first); repository.context.insert(second); try repository.context.save()
        let one = OutgoingMessage(draft: LocalDraft(subject: "Same subject", accountID: first.id)); one.remoteDraftID = "draft"
        let two = OutgoingMessage(draft: LocalDraft(subject: "Same subject", accountID: second.id)); two.remoteDraftID = "draft"
        repository.context.insert(one); repository.context.insert(two)
        try repository.saveDraftLink(accountID: first.id, draftID: "draft", messageID: "m")
        try repository.saveDraftLink(accountID: second.id, draftID: "draft", messageID: "m")
        var links = try repository.context.fetch(FetchDescriptor<StoreMetadata>())
        XCTAssertEqual(DraftLinks.hiddenMessageIDs(outgoing: [one, two], links: links, accountID: first.id), ["\(first.id.uuidString):m"])
        try repository.replaceDraftLinks([], accountID: first.id)
        links = try repository.context.fetch(FetchDescriptor<StoreMetadata>())
        XCTAssertEqual(DraftLinks.hiddenMessageIDs(outgoing: [one, two], links: links, accountID: nil), ["\(second.id.uuidString):m"])
        try repository.removeAccountData(id: second.id)
        XCTAssertTrue(try repository.context.fetch(FetchDescriptor<StoreMetadata>()).isEmpty)
        XCTAssertNotNil(try repository.outgoing(one.id))
    }
}
