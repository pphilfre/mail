import XCTest
@testable import DispatchMail

@MainActor final class MailInteractionRefinementTests: XCTestCase {
    private func receipt(_ subject: String, body: String, sender: String = "PayPal") -> ReceiptSummary? {
        let message = MailMessage(accountID: UUID(), remoteID: UUID().uuidString, remoteThreadID: "transaction",
            sender: MailAddress(name: sender, email: "receipts@example.com"), subject: subject, snippet: "", receivedAt: Date())
        message.cachedText = Data(body.utf8)
        return ReceiptDetector.detect(ReceiptSource(message))
    }
    func testPayPalTransfersAndMerchantPurchasesStayDistinct() throws {
        let transfer = try XCTUnwrap(receipt("You sent a payment", body: "You sent USD 25.00 to Jamie.\nTransaction ID: T123"))
        XCTAssertEqual(transfer.kind, "Transfer")
        XCTAssertEqual(transfer.flow, .outgoing)
        XCTAssertTrue(transfer.signedAmount.hasPrefix("−"))
        let purchase = try XCTUnwrap(receipt("Order confirmation", body: "Seller: Dell\nProduct: Laptop\nOrder number: D123\nOrder total USD 2,000.00", sender: "Dell"))
        XCTAssertEqual(purchase.kind, "Purchase")
        XCTAssertEqual(purchase.merchant, "Dell")
        XCTAssertEqual(purchase.flow, .outgoing)
        XCTAssertEqual(purchase.money?.amount, 2000)
        XCTAssertTrue(purchase.facts.contains(.init(label: "Item", value: "Laptop")))
        XCTAssertTrue(purchase.facts.contains(.init(label: "Order number", value: "D123")))
    }
    func testIncomingRefundsAndUnpaidInvoicesDoNotBecomeSpending() throws {
        let incoming = try XCTUnwrap(receipt("You received a payment", body: "You received GBP 35.00.\nTransaction ID: IN1"))
        XCTAssertEqual(incoming.flow, .incoming)
        XCTAssertTrue(incoming.signedAmount.hasPrefix("+"))
        let refund = try XCTUnwrap(receipt("Refund processed", body: "Refund processed. Total GBP 20.00"))
        XCTAssertEqual(refund.kind, "Refund")
        XCTAssertEqual(refund.flow, .incoming)
        let invoice = try XCTUnwrap(receipt("Your invoice", body: "Invoice number: INV1\nAmount due GBP 200.00"))
        XCTAssertEqual(invoice.flow, .unknown)
        let requested = receipt("Refund requested", body: "Transaction ID: RF1\nTotal GBP 20.00")
        XCTAssertNotEqual(requested?.flow, .incoming)
    }
    func testTotalsOnSeparateLinesAndPromotions() {
        XCTAssertEqual(ReceiptDetector.amount(in: "Subtotal GBP 1800.00\nTax GBP 200.00\nOrder total\nGBP 2000.00")?.amount, 2000)
        XCTAssertNil(receipt("Special offer: Dell laptop", body: "Order total USD 2,000.00"))
    }
    func testActivityKeepsCurrenciesSeparateAndExcludesUnknownDirections() {
        let now = Date()
        func item(_ amount: Decimal, currency: String, flow: ReceiptFlow) -> ReceiptSummary {
            ReceiptSummary(id: UUID(), accountID: UUID(), remoteID: UUID().uuidString, merchant: "Shop", kind: "Purchase",
                money: ReceiptMoney(amount: amount, currency: currency), subject: "Order", senderEmail: "shop@example.com", receivedAt: now, flow: flow)
        }
        let months = ReceiptActivity.months([item(2000, currency: "USD", flow: .outgoing), item(50, currency: "GBP", flow: .incoming),
            item(30, currency: "GBP", flow: .outgoing), item(100, currency: "GBP", flow: .unknown)], currency: "GBP", now: now)
        XCTAssertEqual(months.count, 6)
        XCTAssertEqual(months.last?.incoming, 50)
        XCTAssertEqual(months.last?.outgoing, 30)
    }
    func testDirectionCorrectionsReadOlderSavedReceipts() throws {
        let account = UUID()
        let json = "{\"version\":1,\"accountID\":\"\(account.uuidString)\",\"remoteID\":\"old\",\"inclusion\":\"include\",\"amountReviewed\":false}"
        let old = try JSONDecoder().decode(ReceiptOverride.self, from: Data(json.utf8))
        XCTAssertNil(old.flow)
        var updated = old; updated.flow = .incoming
        let saved = try JSONDecoder().decode(ReceiptOverride.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(saved.flow, .incoming)
    }
    func testWritingLengthContractsRejectSuperficialParaphrases() {
        let source = Array(repeating: "word", count: 200).joined(separator: " ")
        XCTAssertTrue(MailWritingRevision.instruction(.shorten, source: source).contains("80–120 words"))
        XCTAssertFalse(MailWritingRevision.meetsLengthTarget(.shorten, source: source, revision: source))
        XCTAssertTrue(MailWritingRevision.meetsLengthTarget(.shorten, source: source, revision: Array(repeating: "word", count: 100).joined(separator: " ")))
        XCTAssertFalse(MailWritingRevision.meetsLengthTarget(.expand, source: source, revision: source))
        XCTAssertTrue(MailWritingRevision.meetsLengthTarget(.expand, source: source, revision: Array(repeating: "word", count: 300).joined(separator: " ")))
    }
    func testWordDiffShowsRemovedAddedRepeatedAndUnicodeWords() {
        let runs = MailWritingRevision.runs(original: "Hello hello 😀.\nPlease review soon.", revised: "Hello 😀.\nPlease review today.")
        XCTAssertTrue(runs.contains { $0.change == .removed && $0.text.contains("hello") })
        XCTAssertTrue(runs.contains { $0.change == .removed && $0.text.contains("soon.") })
        XCTAssertTrue(runs.contains { $0.change == .added && $0.text.contains("today.") })
        XCTAssertEqual(runs.filter { $0.change != .removed }.map(\.text).joined(), "Hello 😀.\nPlease review today.")
    }
    func testIconFallbackStartsAtRegistrableDomainAndTriesAlternateFormats() {
        let urls = SenderIdentity.iconURLs(email: "orders@news.shop.co.uk", suffixes: MailPublicSuffixes(text: "uk\nco.uk"))
        XCTAssertEqual(urls.first?.absoluteString, "https://shop.co.uk/favicon.ico")
        XCTAssertTrue(urls.contains { $0.absoluteString == "https://shop.co.uk/apple-touch-icon.png" })
        XCTAssertTrue(urls.contains { $0.host == "www.shop.co.uk" })
        XCTAssertTrue(SenderIdentity.iconURLs(email: "person@gmail.com", suffixes: MailPublicSuffixes(text: "com")).isEmpty)
    }
    func testDeclaredIconsResolveRelativeAssetsWithoutTrustingOtherDomains() throws {
        let suffixes = MailPublicSuffixes(text: "com")
        let page = try XCTUnwrap(URL(string: "https://shop.com/"))
        let html = "<link href='/assets/brand.png' rel='shortcut icon'><link rel=\"apple-touch-icon\" href=\"https://cdn.shop.com/logo.png\"><link rel='icon' href='https://unrelated.com/logo.png'><link rel='icon' href='data:image/png,abc'><link rel='icon' href='https://shop.com/logo.svg'>"
        XCTAssertEqual(SenderIdentity.declaredIconURLs(html: html, page: page, suffixes: suffixes).map(\.absoluteString),
            ["https://shop.com/assets/brand.png", "https://cdn.shop.com/logo.png"])
    }
    func testSummaryPreparationIncludesMailboxOwnerForRecipientFocusedBriefs() throws {
        let source = MailSummarySource(sender: "Alex", subject: "Review", text: "Please review the proposal by Friday.", html: nil, reader: "Freddie <freddie@example.com>")
        let input = try MailSummaryPreparation.inputs([source], maximum: 2600).joined()
        XCTAssertTrue(input.contains("The person reading this mailbox: Freddie <freddie@example.com>"))
        XCTAssertTrue(input.contains("Please review the proposal by Friday."))
    }
}
