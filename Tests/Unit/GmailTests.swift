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
        let transport = FixtureTransport([reply("{}", status: 401), reply("{}"), reply("{}")])
        let api = GmailAPI(transport: transport) { force in force ? "new" : "old" }
        try await api.modify("abc", remove: ["UNREAD"])
        try await api.trash("abc")
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(requests[2].httpMethod, "POST")
        XCTAssertEqual(requests[2].url?.path, "/gmail/v1/users/me/messages/abc/trash")
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
        XCTAssertEqual(MailMIME.addresses(draft.to).first?.name, "Last, First")
        XCTAssertEqual(MailMIME.decodedHeader("=?UTF-8?B?SGVsbG8g8J+MjQ==?="), "Hello 🌍")
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
        try repository.apply([dto], accountID: account.id)
        XCTAssertTrue(row.isRead); XCTAssertFalse(row.isInbox); XCTAssertEqual(row.plainTextBody?.trimmingCharacters(in: .whitespacesAndNewlines), "Body")
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
    }
}
