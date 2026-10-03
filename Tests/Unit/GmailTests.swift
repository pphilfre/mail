import Foundation
import SwiftData
import XCTest
@testable import DispatchMail

actor FixtureTransport: MailHTTPTransport {
    var replies: [HTTPReply]
    var requests: [URLRequest] = []
    init(_ replies: [HTTPReply]) { self.replies = replies }
    func execute(_ request: URLRequest) async throws -> HTTPReply {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        return replies.removeFirst()
    }
    func captured() -> [URLRequest] { requests }
}

@MainActor
final class GmailTests: XCTestCase {
    private func reply(_ json: String, status: Int = 200) -> HTTPReply { HTTPReply(data: Data(json.utf8), status: status) }
    func testPKCEAndCallbackStateValidation() throws {
        let config = GoogleConfiguration(clientID: "test.apps.googleusercontent.com", callbackScheme: "com.googleusercontent.apps.test")
        let authorization = try GoogleAuthorization(configuration: config, verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "state")
        XCTAssertEqual(authorization.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(try authorization.code(from: URL(string: config.redirectURI + "?code=code&state=state")!), "code")
        XCTAssertThrowsError(try authorization.code(from: URL(string: config.redirectURI + "?code=code&state=other")!))
        XCTAssertThrowsError(try authorization.code(from: URL(string: config.redirectURI + "?code=a&code=b&state=state")!))
        XCTAssertThrowsError(try authorization.code(from: URL(string: config.callbackScheme + ":/wrong?code=a&state=state")!))
        let items = URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(items.first { $0.name == "scope" }?.value, GoogleConfiguration.scope)
    }
    func testBundledGoogleConfigurationMatchesCallbackRegistration() throws {
        let config = try GoogleConfiguration.load()
        XCTAssertEqual(config.clientID, "350736449780-jdq6jll8nm6kpiq267saoa0qt9dmnli1.apps.googleusercontent.com")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        XCTAssertTrue(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(config.callbackScheme) == true })
    }
    func testRefreshPreservesRefreshTokenAndFormEscaping() async throws {
        let vault = CredentialVault(service: "dispatch.test.\(UUID())")
        let id = UUID()
        let previous = OAuthCredentials(accessToken: "expired", refreshToken: "refresh+&=", expiresAt: .distantPast, grantedScopes: [GoogleConfiguration.scope])
        try await vault.save(previous, for: id)
        let transport = FixtureTransport([reply(#"{"access_token":"fresh","expires_in":3600}"#)])
        let tokens = GoogleTokenManager(configuration: GoogleConfiguration(clientID: "public", callbackScheme: "callback"), vault: vault, transport: transport)
        let access = try await tokens.token(for: id)
        XCTAssertEqual(access, "fresh")
        let stored = try await vault.load(for: id)
        XCTAssertEqual(stored?.refreshToken, previous.refreshToken)
        let requests = await transport.captured()
        let body = String(data: requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("refresh_token=refresh%2B%26%3D"))
        XCTAssertFalse(body.contains("client_secret"))
        _ = try await tokens.token(for: id)
        let count = await transport.captured().count
        XCTAssertEqual(count, 1)
        try await vault.remove(for: id)
    }
    func test401RetriesOnceAndTrashNeverPermanentlyDeletes() async throws {
        let transport = FixtureTransport([reply("{}", status: 401), reply("{}"), reply("{}"), reply("{}")])
        let api = GmailAPI(transport: transport) { force in force ? "new" : "old" }
        try await api.modify("abc", remove: ["UNREAD"])
        try await api.trash("abc")
        _ = try await api.messages(label: "TRASH")
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(requests[2].httpMethod, "POST")
        XCTAssertEqual(requests[2].url?.path, "/gmail/v1/users/me/messages/abc/trash")
        XCTAssertTrue(requests[3].url!.absoluteString.contains("includeSpamTrash=true"))
    }
    func testRateLimitedReadRetriesAndRecovers() async throws {
        let transport = FixtureTransport([
            reply(#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#, status: 403),
            reply("{}", status: 429),
            reply(#"{"emailAddress":"me@example.com","historyId":"1"}"#)
        ])
        let api = GmailAPI(transport: transport, pause: { _ in }) { _ in "token" }
        let profile = try await api.profile()
        XCTAssertEqual(profile.emailAddress, "me@example.com")
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 3)
    }
    func testRateLimitRetriesAreBounded() async throws {
        let transport = FixtureTransport(Array(repeating: reply("{}", status: 429), count: 5))
        let api = GmailAPI(transport: transport, pause: { _ in }) { _ in "token" }
        do { _ = try await api.profile(); XCTFail("Expected throttling") }
        catch { XCTAssertEqual(error as? GmailError, .throttled) }
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 5)
    }
    func testPermissionDeniedDoesNotRetry() async throws {
        let transport = FixtureTransport([reply(#"{"error":{"errors":[{"reason":"insufficientPermissions"}]}}"#, status: 403)])
        let api = GmailAPI(transport: transport, pause: { _ in XCTFail("Must not back off for permissions") }) { _ in "token" }
        do { _ = try await api.profile(); XCTFail("Expected access error") }
        catch { XCTAssertEqual(error as? GmailError, .accessDenied("insufficientPermissions")) }
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 1)
    }
    func testSendIsNotReplayedOnServerFailure() async throws {
        let transport = FixtureTransport([reply("{}", status: 503)])
        let api = GmailAPI(transport: transport, pause: { _ in XCTFail("Must not replay sending") }) { _ in "token" }
        do { _ = try await api.send(raw: "mail", threadID: nil); XCTFail("Expected server error") }
        catch { XCTAssertEqual(error as? GmailError, .http(503)) }
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 1)
    }
    func testInlineImagesExcludeActiveContentAndKeepNestedImages() {
        let image = GmailPart(mimeType: "image/png", headers: [GmailHeader(name: "Content-ID", value: "<logo>")])
        let active = GmailPart(mimeType: "image/svg+xml", headers: [GmailHeader(name: "Content-ID", value: "<active>")])
        let root = GmailPart(mimeType: "multipart/related", parts: [image, active])
        XCTAssertEqual(MailMIME.inlineImages(root).count, 1)
        XCTAssertEqual(MailMIME.inlineImages(root).first?.header("Content-ID"), "<logo>")
    }
    func testHistoryUsesSpecificChangesAndOpaqueCursor() async throws {
        let transport = FixtureTransport([reply(#"{"history":[{"messagesAdded":[{"message":{"id":"one","threadId":"t"}}],"messagesDeleted":[{"message":{"id":"two"}}],"labelsRemoved":[{"message":{"id":"three"},"labelIds":["INBOX"]}]}],"nextPageToken":"next","historyId":"184467440737095516160"}"#)])
        let api = GmailAPI(transport: transport) { _ in "token" }
        let page = try await api.history(since: "184467440737095516150")
        XCTAssertEqual(page.changedIDs, ["one", "three"])
        XCTAssertEqual(page.deletedIDs, ["two"])
        XCTAssertEqual(page.nextPageToken, "next")
        XCTAssertEqual(page.historyId, "184467440737095516160")
        let requests = await transport.captured()
        XCTAssertTrue(requests[0].url!.absoluteString.contains("startHistoryId=184467440737095516150"))
    }
    func testMIMEUnicodeRecipientsThreadingAndInjectionProtection() throws {
        let draft = LocalDraft(to: "\"Last, First\" <person@example.com>", cc: "copy@example.com", bcc: "hidden@example.com",
            subject: String(repeating: "Hello 🌍 ", count: 20), body: "Unicode body café 🌍", inReplyTo: "<original@example.com>", referencesHeader: "<original@example.com>")
        let encoded = try MailMIME.raw(draft, from: "me@example.com")
        let raw = String(data: Base64URL.decode(encoded)!, encoding: .utf8)!
        XCTAssertTrue(raw.contains("In-Reply-To: <original@example.com>"))
        XCTAssertTrue(raw.contains("Bcc: hidden@example.com"))
        XCTAssertTrue(raw.contains("Content-Transfer-Encoding: base64"))
        XCTAssertFalse(raw.contains("🌍"))
        let subjectWords = raw.components(separatedBy: "\r\n").filter { $0.hasPrefix("Subject:") || $0.hasPrefix(" ") }
        XCTAssertTrue(subjectWords.allSatisfy { $0.count < 80 })
        var invalid = draft; invalid.subject = "Hello\r\nBcc: attacker@example.com"
        XCTAssertThrowsError(try MailMIME.raw(invalid, from: "me@example.com"))
        invalid = draft; invalid.to = "not-an-address"
        XCTAssertThrowsError(try MailMIME.raw(invalid, from: "me@example.com"))
        invalid = draft; invalid.subject = "Header\u{0000}value"
        XCTAssertThrowsError(try MailMIME.raw(invalid, from: "me@example.com"))
        XCTAssertEqual(MailMIME.addresses(draft.to).first?.name, "Last, First")
        XCTAssertEqual(MailMIME.decodedHeader("=?UTF-8?B?SGVsbG8g8J+MjQ==?="), "Hello 🌍")
        XCTAssertEqual(MailMIME.decodedHeader(MailMIME.encodedWord(draft.subject)), draft.subject)
        XCTAssertNoThrow(try MailMIME.raw(LocalDraft(subject: "Unaddressed draft"), from: "me@example.com", requireRecipient: false))
    }
    func testHTMLIsTextAndDoesNotKeepScriptsOrTrackingTags() {
        let html = "<html><head><style>hidden</style></head><body><p>Hello &amp; &#x1F30D;</p><script>alert('x')</script><img src='https://tracker.example/image'></body></html>"
        let text = MailMIME.readableHTML(html)
        XCTAssertEqual(text, "Hello & 🌍")
        XCTAssertFalse(text.contains("tracker")); XCTAssertFalse(text.contains("alert"))
    }
    func testProviderUpsertPreservesPendingOverlayAndCursorUntilCommit() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        account.historyID = "old"
        repository.context.insert(account)
        let dto = GmailMessageDTO(id: "a", threadId: "t", labelIds: ["INBOX", "UNREAD"], snippet: "Hello", internalDate: "1000",
            payload: GmailPart(mimeType: "text/plain", headers: [GmailHeader(name: "From", value: "Other <other@example.com>"),
                GmailHeader(name: "Subject", value: "Subject")], body: GmailBody(data: Base64URL.encode(Data("Body".utf8)))))
        try repository.apply([dto], accountID: account.id)
        let row = try XCTUnwrap(repository.message(accountID: account.id, remoteID: "a"))
        try repository.enqueue("archive", message: row)
        try repository.enqueue("read", message: row)
        try repository.enqueue("labelAdd:Label_123", message: row)
        try repository.apply([dto], accountID: account.id)
        XCTAssertTrue(row.isRead); XCTAssertFalse(row.isInbox); XCTAssertEqual(row.plainTextBody?.trimmingCharacters(in: .whitespacesAndNewlines), "Body")
        XCTAssertTrue(row.folderIDs.contains("Label_123"))
        XCTAssertEqual(account.historyID, "old")
        try repository.apply([dto], accountID: account.id, historyID: "new")
        XCTAssertEqual(account.historyID, "new")
        try repository.apply([], deleted: ["a"], accountID: account.id)
        XCTAssertNil(try repository.message(accountID: account.id, remoteID: "a"))
    }
    func testInterruptedSendIsRetainedAndCannotReturnToDrafts() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let draft = LocalDraft(to: "person@example.com", subject: "Maybe sent", accountID: UUID(), remoteThreadID: "thread", inReplyTo: "<message@example.com>")
        try repository.save([draft])
        let row = try XCTUnwrap(repository.outgoing(draft.id))
        XCTAssertEqual(row.localDraft.accountID, draft.accountID)
        XCTAssertEqual(row.localDraft.inReplyTo, draft.inReplyTo)
        row.stateRaw = "sending"; try repository.context.save()
        try repository.recoverInterruptedSends()
        XCTAssertEqual(row.stateRaw, "sendUnconfirmed")
        XCTAssertTrue(try repository.load().isEmpty)
        try repository.save([])
        XCTAssertNotNil(try repository.outgoing(draft.id))
        XCTAssertThrowsError(try repository.save([draft]))
    }

    func testHistoryPaginationFailureKeepsOriginalCursorAndReplaysSafely() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        account.historyID = "100"; repository.context.insert(account); try repository.context.save()
        let vault = CredentialVault(service: "dispatch.test.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let transport = FixtureTransport([
            reply(#"{"labels":[]}"#),
            reply(#"{"history":[{"messagesAdded":[{"message":{"id":"a"}}]}],"nextPageToken":"second","historyId":"200"}"#),
            reply(#"{"id":"a","threadId":"t","labelIds":["INBOX"],"payload":{"headers":[{"name":"Subject","value":"cached"}]}}"#),
            reply("{}", status: 503),
            reply(#"{"labels":[]}"#),
            reply(#"{"history":[{"messagesAdded":[{"message":{"id":"a"}}]}],"historyId":"300"}"#),
            reply(#"{"id":"a","threadId":"t","labelIds":["INBOX"]}"#)
        ])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport)
        await coordinator.sync(account.id)
        XCTAssertEqual(account.historyID, "100")
        XCTAssertNotNil(try repository.message(accountID: account.id, remoteID: "a"))
        XCTAssertNotNil(account.lastSyncError)
        await coordinator.sync(account.id)
        XCTAssertEqual(account.historyID, "300")
        XCTAssertNil(account.lastSyncError)
        XCTAssertEqual(try repository.recentMessages(accountID: account.id).count, 1)
        try await vault.remove(for: account.id)
    }
    func testExpiredHistoryReconcilesDeletedCacheAndDrainsFreshHistory() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        account.historyID = "expired"; repository.context.insert(account)
        let old = MailMessage(accountID: account.id, remoteID: "old", remoteThreadID: "oldthread", sender: MailAddress(email: "other@example.com"), subject: "Old", snippet: "", receivedAt: .distantPast)
        repository.context.insert(old); try repository.context.save()
        let vault = CredentialVault(service: "dispatch.test.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let transport = FixtureTransport([
            reply(#"{"labels":[]}"#), reply("{}", status: 404),
            reply(#"{"emailAddress":"me@example.com","historyId":"baseline"}"#),
            reply(#"{"messages":[{"id":"new"}],"nextPageToken":"older"}"#), reply(#"{"messages":[]}"#),
            reply(#"{"id":"new","threadId":"thread","labelIds":["INBOX"]}"#), reply("{}", status: 404),
            reply(#"{"historyId":"latest"}"#)
        ])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport)
        await coordinator.sync(account.id)
        XCTAssertEqual(account.historyID, "latest"); XCTAssertEqual(account.syncCursor, "older")
        XCTAssertNil(try repository.message(accountID: account.id, remoteID: "old"))
        XCTAssertNotNil(try repository.message(accountID: account.id, remoteID: "new"))
        try await vault.remove(for: account.id)
    }
    func testNetworkFailureDuringSendRetainsCopyAndNeverResends() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        let draft = LocalDraft(to: "other@example.com", subject: "Send", body: "Body", accountID: account.id)
        try repository.save([draft])
        let vault = CredentialVault(service: "dispatch.test.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let transport = FixtureTransport([reply(#"{"emailAddress":"me@example.com","historyId":"1"}"#)])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport)
        do { try await coordinator.send(draft); XCTFail("Expected uncertain send") }
        catch { XCTAssertEqual(error as? GmailError, .uncertainSend) }
        XCTAssertEqual(try repository.outgoing(draft.id)?.stateRaw, "sendUnconfirmed")
        let before = await transport.captured().count
        do { try await coordinator.send(draft); XCTFail("Must not resend") }
        catch { XCTAssertEqual(error as? GmailError, .uncertainSend) }
        let after = await transport.captured().count
        XCTAssertEqual(before, after)
        try await vault.remove(for: account.id)
    }
    func testUncertainRemoteDraftCreationDoesNotCreateDuplicateOnRetry() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        let draft = LocalDraft(subject: "Draft without recipient", body: "Keep me", accountID: account.id)
        try repository.save([draft])
        let vault = CredentialVault(service: "dispatch.test.\(UUID())")
        try await vault.save(OAuthCredentials(accessToken: "token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600), grantedScopes: [GoogleConfiguration.scope]), for: account.id)
        let transport = FixtureTransport([
            reply(#"{"drafts":[]}"#), reply("{}", status: 503),
            reply(#"{"drafts":[]}"#),
            reply(#"{"drafts":[{"id":"rDraft"}]}"#), reply(#"{"id":"rDraft"}"#)
        ])
        let coordinator = GmailCoordinator(repository: repository, vault: vault, transport: transport)
        for _ in 0..<2 {
            do { try await coordinator.saveRemoteDraft(draft); XCTFail("Expected uncertain draft") }
            catch { XCTAssertEqual(error as? GmailError, .uncertainDraft) }
        }
        try await coordinator.saveRemoteDraft(draft)
        let row = try XCTUnwrap(repository.outgoing(draft.id))
        XCTAssertEqual(row.remoteDraftID, "rDraft"); XCTAssertNil(row.lastError)
        let requests = await transport.captured()
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertEqual(requests.filter { $0.httpMethod == "PUT" }.count, 1)
        XCTAssertEqual(try repository.load().count, 1)
        try await vault.remove(for: account.id)
    }
    func testReplyAllHonoursReplyToAndDeduplicatesOwnAddressAndRecipients() {
        let me = MailAddress(email: "me@example.com")
        let sender = MailAddress(email: "sender@example.com")
        let replyTo = MailAddress(email: "reply@example.com")
        let copy = MailAddress(email: "copy@example.com")
        let result = MailReplyRecipients.make(sender: sender, replyTo: [replyTo], to: [me, copy],
            cc: [MailAddress(email: "COPY@example.com"), me, MailAddress(email: "other@example.com")],
            ownEmail: me.email, replyAll: true)
        XCTAssertEqual(result.to, [replyTo.email, copy.email])
        XCTAssertEqual(result.cc, ["other@example.com"])
        let sent = MailReplyRecipients.make(sender: me, replyTo: [], to: [sender], cc: [copy], ownEmail: me.email, replyAll: false)
        XCTAssertEqual(sent.to, [sender.email]); XCTAssertTrue(sent.cc.isEmpty)
    }
}
