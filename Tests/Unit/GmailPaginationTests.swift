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

    func testOlderPageResumesPartialDownloadAndReleasesBusyState() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        let mailbox = GmailMailbox(name: "All Mail")
        try repository.saveGmailPageToken("original", mailbox: mailbox, accountID: account.id)
        let vault = CredentialVault(service: "dispatch.resume.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let denied = reply(#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#, status: 403)
        let page = reply(#"{"messages":[{"id":"a"},{"id":"b"}],"nextPageToken":"next"}"#)
        let transport = FixtureTransport([
            page, reply(#"{"id":"a","threadId":"t","labelIds":["INBOX"]}"#),
            denied, denied, denied, denied, denied,
            page, reply(#"{"id":"b","threadId":"t","labelIds":["INBOX"]}"#)
        ])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport, requestPause: { _ in })
        // Queue a refresh through the real coalescing path, as happens when the
        // app returns to the foreground during an older-page download.
        coordinator.syncing.insert(account.id)
        await coordinator.sync(account.id)
        coordinator.syncing.remove(account.id)
        await coordinator.loadOlder(account.id)
        XCTAssertFalse(coordinator.syncing.contains(account.id))
        XCTAssertNotNil(account.lastSyncError)
        XCTAssertNotNil(try repository.message(accountID: account.id, remoteID: "a"))
        XCTAssertEqual(try repository.gmailPageTokens()[mailbox.pageKey(account.id)], "original")
        await coordinator.loadOlder(account.id)
        XCTAssertFalse(coordinator.syncing.contains(account.id))
        XCTAssertNil(account.lastSyncError)
        XCTAssertNil(coordinator.error)
        XCTAssertEqual(try repository.gmailPageTokens()[mailbox.pageKey(account.id)], "next")
        let requests = await transport.captured()
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("/messages/a") == true }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("/history") == true || $0.url?.path.hasSuffix("/labels") == true }.count, 0)
        try await vault.remove(for: account.id)
    }

    func testMailboxRefreshUsesHistoryAndReusesCachedBodies() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        account.historyID = "1"
        repository.context.insert(account); try repository.context.save()
        try repository.apply([GmailMessageDTO(id: "a", threadId: "t", labelIds: ["INBOX"])], accountID: account.id)
        let vault = CredentialVault(service: "dispatch.reuse.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let transport = FixtureTransport([
            reply(#"{"history":[],"historyId":"2"}"#),
            reply(#"{"messages":[{"id":"a"}],"nextPageToken":"next"}"#)
        ])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport, requestPause: { _ in })
        await coordinator.loadMailbox("Inbox", accountID: account.id)
        XCTAssertNil(coordinator.error)
        XCTAssertEqual(account.historyID, "2")
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.first?.url?.path.hasSuffix("/history") == true)
        XCTAssertFalse(requests.contains { $0.url?.path.hasSuffix("/messages/a") == true })
        try await vault.remove(for: account.id)
    }
}
