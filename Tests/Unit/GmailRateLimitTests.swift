import Foundation
import SwiftData
import XCTest
@testable import DispatchMail

private actor GmailPauseRecorder {
    var delays: [TimeInterval] = []
    func record(_ delay: TimeInterval) { delays.append(delay) }
    func captured() -> [TimeInterval] { delays }
}

private actor ConcurrentGmailTransport: MailHTTPTransport {
    private var active = 0
    private var maximum = 0
    func execute(_ request: URLRequest) async throws -> HTTPReply {
        active += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        return HTTPReply(data: Data(#"{"emailAddress":"me@example.com","historyId":"1"}"#.utf8), status: 200)
    }
    func maximumConcurrentRequests() -> Int { maximum }
}

@MainActor
final class GmailRateLimitTests: XCTestCase {
    private func reply(_ json: String, status: Int = 200, retryAfter: TimeInterval? = nil) -> HTTPReply {
        HTTPReply(data: Data(json.utf8), status: status, retryAfter: retryAfter)
    }

    func testWeightedPacingAndCooldownNeverShortenServerDeadline() {
        var schedule = GmailRequestSchedule()
        XCTAssertEqual(schedule.delay(at: 100), 0)
        schedule.record(cost: 20, at: 100)
        XCTAssertEqual(schedule.delay(at: 100), 1.0 / 3.0, accuracy: 0.0001)
        schedule.deferRequests(for: 120, at: 100)
        schedule.deferRequests(for: 1, at: 101)
        XCTAssertEqual(schedule.delay(at: 110), 110)
        XCTAssertTrue(schedule.isCoolingDown(at: 110))
        XCTAssertEqual(schedule.delay(at: 221), 0)
        XCTAssertFalse(schedule.isCoolingDown(at: 221))
        XCTAssertEqual(GmailAPI.quotaCost("messages/a", method: "GET"), 20)
        XCTAssertEqual(GmailAPI.quotaCost("threads/a", method: "GET"), 40)
        XCTAssertEqual(GmailAPI.quotaCost("drafts", method: "POST"), 10)
    }

    func testRetryAfterParsesSecondsAndHTTPDate() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(URLSessionMailTransport.retryDelay("120", now: now), 120)
        XCTAssertEqual(URLSessionMailTransport.retryDelay("Thu, 01 Jan 1970 00:02:00 GMT", now: now), 120)
        XCTAssertNil(URLSessionMailTransport.retryDelay("invalid", now: now))
    }

    func testRateLimitedMutationRemainsTemporaryAndSharesCooldownWithReads() async throws {
        let transport = FixtureTransport([
            reply(#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#, status: 403, retryAfter: 120),
            reply(#"{"emailAddress":"me@example.com","historyId":"1"}"#)
        ])
        let pauses = GmailPauseRecorder()
        let api = GmailAPI(transport: transport, pause: { await pauses.record($0) }) { _ in "fixture" }
        do { try await api.modify("a", remove: ["UNREAD"]); XCTFail("Expected temporary rate limit") }
        catch { XCTAssertEqual(error as? GmailError, .throttled) }
        _ = try await api.profile()
        let requests = await transport.captured()
        let delays = await pauses.captured()
        XCTAssertEqual(requests.count, 2) // No automatic mutation replay.
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertGreaterThan(delays.first ?? 0, 119)
    }

    func testStructuredReasonsAndPermissionFailuresArePreservedForMutations() async throws {
        XCTAssertEqual(GmailAPI.errorReason(Data(#"{"error":{"details":[{"reason":"RATE_LIMIT_EXCEEDED"}]}}"#.utf8)), "RATE_LIMIT_EXCEEDED")
        XCTAssertEqual(GmailAPI.errorReason(Data(#"{"error":{"errors":[{"reason":"private-server-content"}]}}"#.utf8)), "forbidden")
        let transport = FixtureTransport([reply(#"{"error":{"details":[{"reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#, status: 403)])
        let api = GmailAPI(transport: transport) { _ in "fixture" }
        do { try await api.modify("a", add: ["STARRED"]); XCTFail("Expected permission failure") }
        catch { XCTAssertEqual(error as? GmailError, .accessDenied("ACCESS_TOKEN_SCOPE_INSUFFICIENT")) }
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 1)
    }

    func testReadRetryHonorsLongRetryAfter() async throws {
        let transport = FixtureTransport([
            reply("{}", status: 429, retryAfter: 120),
            reply(#"{"emailAddress":"me@example.com","historyId":"1"}"#)
        ])
        let pauses = GmailPauseRecorder()
        let api = GmailAPI(transport: transport, pause: { await pauses.record($0) }) { _ in "fixture" }
        _ = try await api.profile()
        let delays = await pauses.captured()
        XCTAssertGreaterThan(delays.first ?? 0, 119)
    }

    func testConcurrentCallersShareOneTransportSlot() async throws {
        let transport = ConcurrentGmailTransport()
        let api = GmailAPI(transport: transport, pause: { _ in }) { _ in "fixture" }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { _ = try await api.profile() } }
            try await group.waitForAll()
        }
        let maximum = await transport.maximumConcurrentRequests()
        XCTAssertEqual(maximum, 1)
    }

    func testTemporaryMutationRejectionIsNotPermanentlyPaused() async throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        let message = MailMessage(accountID: account.id, remoteID: "a", remoteThreadID: "t",
            sender: MailAddress(name: nil, email: "sender@example.com"), subject: "Test", snippet: "", receivedAt: Date())
        message.folderIDs = ["INBOX", "UNREAD"]; message.isRead = false
        repository.context.insert(message); try repository.context.save()
        try repository.enqueue("read", message: message)
        let transport = FixtureTransport([reply(#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#, status: 403)])
        let coordinator = GmailCoordinator(repository: repository, transport: transport)
        let api = GmailAPI(transport: transport) { _ in "fixture" }
        do { try await coordinator.flush(account.id, api: api); XCTFail("Expected throttling") }
        catch { XCTAssertEqual(error as? GmailError, .throttled) }
        let pending = try repository.context.fetch(FetchDescriptor<PendingMailOperation>())
        XCTAssertEqual(pending.count, 1)
        XCTAssertNil(pending.first?.nextAttemptAt)
    }
}
