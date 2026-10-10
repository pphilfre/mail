import XCTest
@testable import DispatchMail

@MainActor
final class ReaderAndConnectivityTests: XCTestCase {
    func testOnlyReturningConnectivitySignalsAutomaticRetry() {
        let connectivity = NetworkConnectivity(startMonitoring: false)
        connectivity.receive(true)
        connectivity.receive(true) // Wi-Fi/cellular handover with a usable path.
        XCTAssertEqual(connectivity.reconnectionCount, 0)
        connectivity.receive(false)
        connectivity.receive(false)
        connectivity.receive(true)
        XCTAssertEqual(connectivity.reconnectionCount, 1)
        connectivity.receive(true)
        XCTAssertEqual(connectivity.reconnectionCount, 1)
        connectivity.receive(false); connectivity.receive(true)
        XCTAssertEqual(connectivity.reconnectionCount, 2)
    }
    func testRepeatedThreadOpenReusesRecentRefreshAndRetryBypassesIt() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        let mail = MailMessage(accountID: account.id, remoteID: "m", remoteThreadID: "t", sender: MailAddress(email: "sender@example.com"), subject: "Mail", snippet: "", receivedAt: Date())
        let vault = CredentialVault(service: "dispatch.reader-cache.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let reply = HTTPReply(data: Data(#"{"id":"t","messages":[]}"#.utf8), status: 200)
        let transport = FixtureTransport([reply, reply])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport, requestPause: { _ in })
        try await coordinator.loadThread(mail); try await coordinator.loadThread(mail)
        let first = await transport.captured(); XCTAssertEqual(first.count, 1)
        try await coordinator.loadThread(mail, force: true)
        let retried = await transport.captured(); XCTAssertEqual(retried.count, 2)
        try await vault.remove(for: account.id)
    }
    func testNativePlainTextPreservesLinksAndLiteralMarkup() {
        let text = "Read <b>literal</b> at https://example.com"
        let linked = MailPlainText.linked(text)
        XCTAssertEqual(String(linked.characters), text)
        XCTAssertTrue(linked.runs.contains { $0.link?.host == "example.com" })
    }

    func testRemoteImagePromptIgnoresPlainHTMLLinksAndEmbeddedImages() {
        XCTAssertFalse(MailMIME.hasRemoteImages("<p>Hello</p><a href='https://example.com'>Link</a>"))
        XCTAssertFalse(MailMIME.hasRemoteImages("<img src='data:image/png;base64,AAAA'><img src='cid:logo'>"))
        XCTAssertFalse(MailMIME.hasRemoteImages("<img data-src='https://example.com/photo.jpg'>"))
        XCTAssertTrue(MailMIME.hasRemoteImages("<IMG SRC = 'https://example.com/photo.jpg'>"))
        XCTAssertTrue(MailMIME.hasRemoteImages("<img src=//example.com/photo.jpg>"))
        XCTAssertTrue(MailMIME.hasRemoteImages("<div style='background-image: url(https://example.com/bg.jpg)'>Hello</div>"))
        XCTAssertTrue(MailMIME.hasRemoteImages("<img srcset='data:image/png;base64,AAAA 1x, https://example.com/2x.png 2x'>"))
    }

    func testThreadFetchFailurePreservesCacheAndDoesNotReplaceOtherAccountError() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        let message = MailMessage(accountID: account.id, remoteID: "cached", remoteThreadID: "thread",
            sender: MailAddress(email: "other@example.com"), subject: "Saved", snippet: "", receivedAt: Date())
        message.cachedText = Data("Offline body".utf8)
        repository.context.insert(message); try repository.context.save()
        let vault = CredentialVault(service: "dispatch.reader.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: FixtureTransport([]))
        coordinator.error = "Other account error"
        do { try await coordinator.loadThread(message); XCTFail("Expected offline failure") }
        catch { XCTAssertEqual(message.plainTextBody, "Offline body") }
        XCTAssertEqual(coordinator.error, "Other account error")
        try await vault.remove(for: account.id)
    }
}
