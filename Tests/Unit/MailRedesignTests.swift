import XCTest
import SwiftData
@testable import DispatchMail

@MainActor final class MailRedesignTests: XCTestCase {
    private func message(_ account: MailAccount, id: String = "one", thread: String = "thread") -> MailMessage {
        MailMessage(accountID: account.id, remoteID: id, remoteThreadID: thread,
            sender: MailAddress(name: "Alex", email: "alex@example.com"), subject: "Plans", snippet: "Hello", receivedAt: Date())
    }
    func testSecurityNeverClaimsAVerdictAndObservationsDoNotFetchLinks() {
        let report = MailSecurityObservations(html: #"<a href="http://bit.ly/abc">Open</a><a href="https://example.com/?a=1&amp;b=2">Visit</a><img src="https://example.com/pixel" width="1" height="1">"#, text: "https://example.com/?a=1&b=2")
        XCTAssertEqual(MailSecurityObservations.statusSymbol, "questionmark.circle")
        XCTAssertTrue(report.hasRemoteImages)
        XCTAssertEqual(report.possibleTrackingPixels, 1)
        XCTAssertEqual(report.links.count, 2)
        XCTAssertEqual(report.links[0].concerns.count, 2)
        XCTAssertEqual(report.links[1].destination, "https://example.com/?a=1&b=2")
        XCTAssertTrue(report.links[1].concerns.isEmpty)
    }
    func testSecurityEmptyContentAndKnownHash() {
        let report = MailSecurityObservations(html: "", text: "No links here")
        XCTAssertTrue(report.links.isEmpty); XCTAssertFalse(report.hasRemoteImages)
        XCTAssertEqual(report.possibleTrackingPixels, 0)
        XCTAssertEqual(MailSecurityObservations.sha256(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testSecurityListsCredentialsAndInternationalDomainsWithoutCallingThemSafe() {
        let report = MailSecurityObservations(html: #"<a href="https://trusted.example@xn--pple-43d.example/login">Account</a><a href="javascript:alert(1)">Bad</a>"#, text: "")
        XCTAssertEqual(report.links.count, 1)
        XCTAssertEqual(report.links[0].host, "xn--pple-43d.example")
        XCTAssertEqual(report.links[0].concerns.count, 2)
    }
    func testOrganisationPersistsAcrossFetchesAndKeepsAccountsSeparate() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let first = MailAccount(provider: .gmail, email: "one@example.com")
        let second = MailAccount(provider: .gmail, email: "two@example.com")
        let row = message(first)
        let sibling = message(first, id: "two")
        let other = message(second)
        for account in [first, second] { repository.context.insert(account) }
        for row in [row, sibling, other] { repository.context.insert(row) }
        try repository.context.save()
        let now = Date()
        try repository.organise(row, pinned: true, snoozedUntil: now.addingTimeInterval(60))
        let values = MailLocalOrganisation.values(try repository.context.fetch(FetchDescriptor<StoreMetadata>()))
        let saved = try XCTUnwrap(values[MailLocalOrganisation.key(sibling)])
        XCTAssertTrue(saved.pinned); XCTAssertTrue(saved.isSnoozed(at: now))
        XCTAssertFalse(saved.isSnoozed(at: now.addingTimeInterval(60)))
        XCTAssertNil(values[MailLocalOrganisation.key(other)])
        try repository.organise(row, clearSnooze: true)
        let cleared = MailLocalOrganisation.values(try repository.context.fetch(FetchDescriptor<StoreMetadata>()))
        XCTAssertTrue(cleared[MailLocalOrganisation.key(row)]?.pinned == true)
        XCTAssertNil(cleared[MailLocalOrganisation.key(row)]?.snoozedUntil)
        try repository.removeAccountData(id: first.id)
        XCTAssertTrue(MailLocalOrganisation.values(try repository.context.fetch(FetchDescriptor<StoreMetadata>())).isEmpty)
    }
    func testMoveQueuesSingleOperationAndUndoRestoresInboxWithoutRemovingUnrelatedLabels() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "one@example.com")
        let row = message(account); row.folderIDs = ["INBOX", "UNREAD", "Label_old"]; MailRepository.flags(row)
        repository.context.insert(account); repository.context.insert(row); try repository.context.save()
        let now = Date()
        let record = try XCTUnwrap(repository.enqueueBatch("move:Label_new", messages: [row], now: now))
        XCTAssertFalse(row.isInbox); XCTAssertTrue(row.folderIDs.contains("Label_new"))
        XCTAssertEqual(try repository.context.fetch(FetchDescriptor<PendingMailOperation>()).count, 1)
        _ = try repository.undoTriage(record.id, now: now.addingTimeInterval(1))
        XCTAssertTrue(row.isInbox); XCTAssertFalse(row.folderIDs.contains("Label_new"))
        XCTAssertTrue(row.folderIDs.contains("Label_old")); XCTAssertFalse(row.isRead)
    }
    func testOriginalMessageUsesRawGmailEndpointAndPreservesBytes() async throws {
        let data = Data("From: alex@example.com\r\nSubject: Plans\r\n\r\nOriginal body".utf8)
        let reply = try JSONSerialization.data(withJSONObject: ["raw": Base64URL.encode(data)])
        let transport = FixtureTransport([HTTPReply(data: reply, status: 200)])
        let api = GmailAPI(transport: transport, pause: { _ in }) { _ in "token" }
        let result = try await api.originalMessage("one")
        XCTAssertEqual(result, data)
        let requests = await transport.captured()
        XCTAssertEqual(requests[0].url?.path, "/gmail/v1/users/me/messages/one")
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "format" }?.value, "raw")
    }
    func testPDFContainsPagesWithoutLoadingRemoteImages() throws {
        let account = MailAccount(provider: .gmail, email: "one@example.com")
        let row = message(account)
        row.cachedText = Data(String(repeating: "A long message with readable content.\n", count: 150).utf8)
        let export = try MessageUtilities.pdf(row)
        defer { try? FileManager.default.removeItem(at: export.url) }
        let data = try Data(contentsOf: export.url)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertGreaterThan(data.count, 1000)
    }
}
