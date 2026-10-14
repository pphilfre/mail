import Foundation
import XCTest
@testable import DispatchMail

@MainActor final class ReceiptDetectionCacheTests: XCTestCase {
    func testReopeningUsesPersistedResultsAndNewBodyInvalidatesThem() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "receipts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let message = MailMessage(accountID: UUID(), remoteID: "receipt", remoteThreadID: "receipt",
            sender: MailAddress(email: "shop@example.com"), subject: "Receipt", snippet: "Total GBP 22.00", receivedAt: Date())
        let source = ReceiptSource(message)
        let initial = await ReceiptDetectionCache(root: root).receipts(for: [source])
        XCTAssertEqual(initial.first?.money?.amount, Decimal(22))
        let file = root.appending(path: "detections-v1.json")
        let bytes = try Data(contentsOf: file)
        let reopened = ReceiptDetectionCache(root: root)
        let restored = await reopened.receipts(for: [source])
        XCTAssertEqual(restored, initial)
        XCTAssertEqual(try Data(contentsOf: file), bytes, "Cache hits must not rewrite or re-detect unchanged messages")
        message.cachedText = Data("Total GBP 45.00".utf8)
        let updated = await reopened.receipts(for: [ReceiptSource(message)])
        XCTAssertEqual(updated.first?.money?.amount, Decimal(45))
        XCTAssertNotEqual(try Data(contentsOf: file), bytes)
        let empty = await reopened.receipts(for: [])
        XCTAssertTrue(empty.isEmpty, "Removed messages must never leak from cached results")
    }

    func testNegativeDetectionsPersistAndAccountScopesStaySeparate() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "receipts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = MailMessage(accountID: UUID(), remoteID: "same-id", remoteThreadID: "thread",
            sender: MailAddress(email: "shop@example.com"), subject: "Hello", snippet: "See you tomorrow", receivedAt: Date())
        let second = MailMessage(accountID: UUID(), remoteID: "same-id", remoteThreadID: "thread",
            sender: MailAddress(email: "shop@example.com"), subject: "Receipt", snippet: "Total GBP 10.00", receivedAt: Date())
        let cache = ReceiptDetectionCache(root: root)
        let negative = await cache.receipts(for: [ReceiptSource(first)])
        XCTAssertTrue(negative.isEmpty)
        let file = root.appending(path: "detections-v1.json")
        let bytes = try Data(contentsOf: file)
        let reopened = ReceiptDetectionCache(root: root)
        let negativeAgain = await reopened.receipts(for: [ReceiptSource(first)])
        XCTAssertTrue(negativeAgain.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let positive = await reopened.receipts(for: [ReceiptSource(second)])
        XCTAssertEqual(positive.map(\.accountID), [second.accountID])
        first.subject = "Receipt"; first.cachedText = Data("Total GBP 20.00".utf8)
        let changed = await reopened.receipts(for: [ReceiptSource(first)])
        XCTAssertEqual(changed.first?.money?.amount, Decimal(20))
        XCTAssertEqual(changed.map(\.accountID), [first.accountID])
    }
}
