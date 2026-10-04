import XCTest
@testable import DispatchMail

@MainActor
final class GmailPaginationTests: XCTestCase {
    private func reply(_ json: String, status: Int = 200) -> HTTPReply { HTTPReply(data: Data(json.utf8), status: status) }

    func testOlderMailboxPagesRetainFilterAndPersistIndependentCursors() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        account.syncCursor = "all-mail-cursor"
        repository.context.insert(account); try repository.context.save()
        let vault = CredentialVault(service: "dispatch.pagination.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let transport = FixtureTransport([
            reply(#"{"messages":[],"nextPageToken":"sent-next"}"#),
            reply(#"{"messages":[],"nextPageToken":"label-next"}"#),
            reply(#"{"messages":[]}"#),
            reply(#"{"messages":[],"nextPageToken":"label-last"}"#)
        ])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport)
        await coordinator.loadMailbox("Sent", accountID: account.id)
        await coordinator.loadMailbox("Inbox", accountID: account.id, labelID: "Label_1")
        XCTAssertTrue(coordinator.hasOlder(account.id, mailbox: "Sent"))
        XCTAssertTrue(coordinator.hasOlder(account.id, mailbox: "Inbox", labelID: "Label_1"))
        await coordinator.loadOlder(account.id, mailbox: "Sent")
        XCTAssertFalse(coordinator.hasOlder(account.id, mailbox: "Sent"))
        XCTAssertTrue(coordinator.hasOlder(account.id, mailbox: "Inbox", labelID: "Label_1"))
        XCTAssertEqual(account.syncCursor, "all-mail-cursor")
        await coordinator.loadOlder(account.id, mailbox: "Inbox", labelID: "Label_1")
        let requests = await transport.captured()
        let sentQuery = URLComponents(url: try XCTUnwrap(requests[2].url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(sentQuery.first { $0.name == "labelIds" }?.value, "SENT")
        XCTAssertEqual(sentQuery.first { $0.name == "pageToken" }?.value, "sent-next")
        let labelQuery = URLComponents(url: try XCTUnwrap(requests[3].url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(labelQuery.first { $0.name == "labelIds" }?.value, "Label_1")
        XCTAssertEqual(labelQuery.first { $0.name == "pageToken" }?.value, "label-next")
        let reopened = GmailCoordinator(repository: repository, vault: vault, transport: transport)
        XCTAssertFalse(reopened.hasOlder(account.id, mailbox: "Sent"))
        XCTAssertTrue(reopened.hasOlder(account.id, mailbox: "Inbox", labelID: "Label_1"))
        XCTAssertTrue(reopened.hasOlder(account.id, mailbox: "All Mail"))
        try await vault.remove(for: account.id)
    }

    func testFailedMessageFetchDoesNotAdvanceCursor() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        let mailbox = GmailMailbox(name: "Trash")
        try repository.saveGmailPageToken("original", mailbox: mailbox, accountID: account.id)
        let vault = CredentialVault(service: "dispatch.pagination.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let transport = FixtureTransport([reply(#"{"messages":[{"id":"a"}],"nextPageToken":"new"}"#)])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport)
        await coordinator.loadOlder(account.id, mailbox: "Trash")
        XCTAssertNotNil(coordinator.error)
        XCTAssertEqual(try repository.gmailPageTokens()[mailbox.pageKey(account.id)], "original")
        let requests = await transport.captured()
        let query = URLComponents(url: try XCTUnwrap(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "includeSpamTrash" }?.value, "true")
        try await vault.remove(for: account.id)
    }

    func testAccountRemovalClearsOnlyItsPaginationMetadata() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let first = MailAccount(provider: .gmail, email: "first@example.com")
        let second = MailAccount(provider: .gmail, email: "second@example.com")
        repository.context.insert(first); repository.context.insert(second); try repository.context.save()
        let mailbox = GmailMailbox(name: "Inbox")
        try repository.saveGmailPageToken("one", mailbox: mailbox, accountID: first.id)
        try repository.saveGmailPageToken("two", mailbox: mailbox, accountID: second.id)
        let firstID = first.id
        try repository.removeAccountData(id: firstID)
        let tokens = try repository.gmailPageTokens()
        XCTAssertNil(tokens[mailbox.pageKey(firstID)])
        XCTAssertEqual(tokens[mailbox.pageKey(second.id)], "two")
    }
}
