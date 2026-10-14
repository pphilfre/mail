import Foundation
import SwiftData
import XCTest
import UIKit
import CryptoKit
@testable import DispatchMail

@MainActor final class MailUIRefreshTests: XCTestCase {
    func testSummarySurvivesReopeningAndInvalidatesChangedContent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "summary-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = [MailSummarySource(sender: "Alex", subject: "Approval", text: "Please approve £45.", html: nil)]
        let cache = MailSummaryCache(root: root)
        await cache.store(MailSummaryResult(text: "Approve £45.", generated: true), for: original)
        let reopened = MailSummaryCache(root: root)
        let saved = await reopened.value(for: original)
        XCTAssertEqual(saved?.text, "Approve £45.")
        let changed = [MailSummarySource(sender: "Alex", subject: "Approval", text: "Please approve £90.", html: nil)]
        let stale = await reopened.value(for: changed)
        XCTAssertNil(stale)
        await reopened.clear()
        let cleared = await MailSummaryCache(root: root).value(for: original)
        XCTAssertNil(cleared)
    }
    func testIncompleteAndUngeneratedSummariesAreNeverPersisted() async {
        let root = FileManager.default.temporaryDirectory.appending(path: "summary-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = [MailSummarySource(sender: "Alex", subject: "Plans", text: "Meet on Friday.", html: nil)]
        let cache = MailSummaryCache(root: root)
        await cache.store(MailSummaryResult(text: "Meet on Friday.", generated: false), for: sources)
        var result = await cache.value(for: sources)
        XCTAssertNil(result)
        await cache.store(MailSummaryResult(text: "Meet on Friday.", generated: true, missingBodies: 1), for: sources)
        result = await cache.value(for: sources)
        XCTAssertNil(result)
    }
    func testSummaryKeySeparatesFieldsHTMLAndRecipientContext() {
        let one = [MailSummarySource(sender: "ab", subject: "c", text: nil, html: "<p>Hello</p>")]
        let two = [MailSummarySource(sender: "a", subject: "bc", text: nil, html: "<p>Hello</p>")]
        XCTAssertNotEqual(MailSummaryCache.key(one), MailSummaryCache.key(two))
        var edited = one
        edited[0] = MailSummarySource(sender: "ab", subject: "c", text: nil, html: "<p>Changed</p>")
        XCTAssertNotEqual(MailSummaryCache.key(one), MailSummaryCache.key(edited))
    }
    func testDiscordDeclaredIconAllowsOnlyItsPublishedCDNNamespace() throws {
        let page = try XCTUnwrap(URL(string: "https://discord.com/"))
        let suffixes = MailPublicSuffixes(text: "com\nnet")
        let icon = "https://cdn.prod.website-files.com/6257adef93867e50d84d30e2/icon.png"
        let html = "<link rel='shortcut icon' href='\(icon)'><link rel='icon' href='https://unrelated.com/icon.png'>"
        XCTAssertEqual(SenderIdentity.declaredIconURLs(html: html, page: page, suffixes: suffixes).map(\.absoluteString), [icon])
        let other = try XCTUnwrap(URL(string: "https://example.com/"))
        XCTAssertEqual(SenderIdentity.declaredIconURLs(html: html, page: other, suffixes: suffixes), [])
        let wrongSite = "<link rel='icon' href='https://cdn.prod.website-files.com/another-site/icon.png'>"
        XCTAssertEqual(SenderIdentity.declaredIconURLs(html: wrongSite, page: page, suffixes: suffixes), [])
    }
    func testPersistedFaviconLoadsWithoutAWebsiteRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "icon-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try LocalMailProtection.protectDirectory(root)
        let url = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try XCTUnwrap(image.pngData())
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        try data.write(to: root.appending(path: key + ".png"))
        try JSONEncoder().encode(["example.com": url]).write(to: root.appending(path: "resolved.json"))
        let result = await CompanyIconStore(root: root).icon(email: "person@example.com")
        XCTAssertEqual(result, data)
    }
    func testReceiptTypeAndLegacyCorrectionsRoundTrip() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        let message = MailMessage(accountID: account.id, remoteID: "receipt", remoteThreadID: "receipt",
            sender: MailAddress(email: "billing@example.com"), subject: "Receipt", snippet: "Total £45", receivedAt: Date())
        var correction = ReceiptOverride(accountID: account.id, remoteID: message.remoteID)
        correction.kind = "Invoice"
        try repository.saveReceipt(correction)
        let row = try XCTUnwrap(repository.metadata(correction.key))
        let saved = try ReceiptOverride.decode(row)
        XCTAssertEqual(saved.apply(to: ReceiptSource(message), detected: nil)?.kind, "Invoice")
        let legacy = StoreMetadata(key: correction.key, value: "{\"version\":1,\"accountID\":\"\(account.id)\",\"remoteID\":\"receipt\",\"inclusion\":\"include\",\"amountReviewed\":false}")
        XCTAssertNil(try ReceiptOverride.decode(legacy).kind)
        correction.kind = "Unsupported"
        XCTAssertThrowsError(try repository.saveReceipt(correction))
    }
}
