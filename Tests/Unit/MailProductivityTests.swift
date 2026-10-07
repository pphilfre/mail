import Foundation
import SwiftData
import XCTest
@testable import DispatchMail

@MainActor
final class MailProductivityTests: XCTestCase {
    private func message(accountID: UUID, subject: String = "Your receipt", body: String = "Order total £22.00", id: String = "mail") -> MailMessage {
        let value = MailMessage(accountID: accountID, remoteID: id, remoteThreadID: "thread",
            sender: MailAddress(name: "Paper & Ink", email: "receipts@example.com"), subject: subject,
            snippet: "", receivedAt: Date(timeIntervalSince1970: 1000))
        value.cachedText = Data(body.utf8)
        return value
    }
    func testTaskPersistsNotesDueDateAndCompletionWithoutModifyingMail() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        let container = try MailStorage.open(at: directory.appending(path: "mail.sqlite"))
        let repository = MailRepository(context: container.mainContext)
        repository.context.insert(account)
        let mail = message(accountID: account.id)
        mail.folderIDs = ["INBOX", "UNREAD"]; MailRepository.flags(mail)
        repository.context.insert(mail); try repository.context.save()
        var task = try repository.task(for: mail)
        task.title = "  Check order  "; task.notes = "Ask about delivery"; task.dueAt = Date(timeIntervalSince1970: 2000)
        try repository.saveTask(task)
        let reopened = try MailStorage.open(at: directory.appending(path: "mail.sqlite"))
        let other = MailRepository(context: reopened.mainContext)
        var saved = try MailTask.decode(XCTUnwrap(other.metadata(task.key)))
        XCTAssertEqual(saved.title, "Check order"); XCTAssertEqual(saved.notes, task.notes); XCTAssertEqual(saved.dueAt, task.dueAt)
        XCTAssertTrue(mail.isInbox); XCTAssertFalse(mail.isRead)
        XCTAssertTrue(try repository.context.fetch(FetchDescriptor<PendingMailOperation>()).isEmpty)
        let same = try repository.task(for: mail)
        XCTAssertEqual(same.id, task.id)
        saved.completedAt = Date(); try other.saveTask(saved)
        XCTAssertTrue(try MailTask.decode(XCTUnwrap(other.metadata(task.key))).isCompleted)
        try other.deleteTask(saved)
        XCTAssertNil(try other.metadata(task.key))
        XCTAssertNotNil(try other.message(accountID: account.id, remoteID: mail.remoteID))
    }
    func testTaskConversationDeduplicationAndAccountDeletionAreScoped() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let first = MailAccount(provider: .gmail, email: "first@example.com")
        let second = MailAccount(provider: .gmail, email: "second@example.com")
        repository.context.insert(first); repository.context.insert(second)
        let firstMail = message(accountID: first.id), next = message(accountID: first.id, id: "next"), secondMail = message(accountID: second.id)
        repository.context.insert(firstMail); repository.context.insert(next); repository.context.insert(secondMail)
        try repository.context.save()
        let firstTask = try repository.task(for: firstMail), secondTask = try repository.task(for: secondMail)
        try repository.saveTask(firstTask); try repository.saveTask(secondTask)
        XCTAssertEqual(try repository.task(for: next).id, firstTask.id)
        XCTAssertNotEqual(firstTask.id, secondTask.id)
        try repository.saveReceipt(ReceiptOverride(accountID: first.id, remoteID: firstMail.remoteID))
        try repository.saveReceipt(ReceiptOverride(accountID: second.id, remoteID: secondMail.remoteID))
        try repository.removeAccountData(id: first.id)
        XCTAssertNil(try repository.metadata(firstTask.key)); XCTAssertNotNil(try repository.metadata(secondTask.key))
        XCTAssertNil(try repository.metadata(ReceiptOverride.prefix(first.id) + firstMail.remoteID))
        XCTAssertNotNil(try repository.metadata(ReceiptOverride.prefix(second.id) + secondMail.remoteID))
        var empty = secondTask; empty.title = "  "
        XCTAssertThrowsError(try repository.saveTask(empty))
    }
    func testTaskDateSectionsUseCalendarDays() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 18))!
        var task = MailTask(accountID: UUID(), remoteMessageID: "m", remoteThreadID: "t", title: "Task", subject: "Email", sender: "person@example.com")
        XCTAssertEqual(task.section(now: now, calendar: calendar), "No due date")
        task.dueAt = calendar.startOfDay(for: now)
        XCTAssertEqual(task.section(now: now, calendar: calendar), "Today")
        task.dueAt = calendar.date(byAdding: .day, value: -1, to: now)
        XCTAssertEqual(task.section(now: now, calendar: calendar), "Overdue")
        task.dueAt = calendar.date(byAdding: .day, value: 1, to: now)
        XCTAssertEqual(task.section(now: now, calendar: calendar), "Upcoming")
        task.completedAt = now
        XCTAssertEqual(task.section(now: now, calendar: calendar), "Completed")
    }
    func testReceiptTotalOutranksSubtotalTaxAndShippingAndKeepsCurrency() {
        let mail = message(accountID: UUID(), body: "Subtotal £19.00\nShipping £2.00\nTax £3.00\nOrder total £24.00")
        let receipt = ReceiptDetector.detect(ReceiptSource(mail))
        XCTAssertEqual(receipt?.merchant, "Paper & Ink")
        XCTAssertEqual(receipt?.money, ReceiptMoney(amount: 24, currency: "GBP"))
        XCTAssertEqual(ReceiptDetector.amount(in: "Grand total EUR 1.234,56"), ReceiptMoney(amount: Decimal(string: "1234.56")!, currency: "EUR"))
        XCTAssertEqual(ReceiptDetector.amount(in: "Amount paid 1,234.56 USD"), ReceiptMoney(amount: Decimal(string: "1234.56")!, currency: "USD"))
        XCTAssertEqual(ReceiptDetector.amount(in: "Total $49.99")?.currency, "$", "Do not silently assume USD")
        XCTAssertEqual(ReceiptDetector.amount(in: "Total CHF 1 234.50")?.amount, Decimal(string: "1234.50"))
        XCTAssertEqual(ReceiptDetector.amount(in: "Subtotal EUR 10,00\nTax EUR 2,00\nGrand total EUR 12,00")?.amount, 12)
        XCTAssertNil(ReceiptDetector.amount(in: "Item £10.00\nTax £2.00"))
        XCTAssertNil(ReceiptDetector.decimal("1,23,456"))
        XCTAssertNil(ReceiptDetector.decimal("123.45.67"))
        XCTAssertNil(ReceiptDetector.decimal("-20.00"))
        XCTAssertEqual(ReceiptDetector.enteredAmount("12,34"), Decimal(string: "12.34"))
        XCTAssertNil(ReceiptDetector.enteredAmount("1.234"), "Do not interpret an entered decimal as a thousands value")
    }
    func testReceiptAvoidsPromotionsFailuresAndWorksFromCachedHTML() {
        let id = UUID()
        XCTAssertNil(ReceiptDetector.detect(ReceiptSource(message(accountID: id, subject: "Special offer: your order", body: "Order total £20.00"))))
        XCTAssertNil(ReceiptDetector.detect(ReceiptSource(message(accountID: id, subject: "Payment failed", body: "Receipt total £20.00"))))
        XCTAssertNil(ReceiptDetector.detect(ReceiptSource(message(accountID: id, subject: "Lunch plans", body: "It costs £12.00"))))
        let unknown = ReceiptDetector.detect(ReceiptSource(message(accountID: id, subject: "Your receipt", body: "Thank you")))
        XCTAssertNotNil(unknown); XCTAssertNil(unknown?.money)
        let html = message(accountID: id, subject: "Invoice 182", body: "")
        html.cachedText = nil; html.cachedHTML = Data("<p>Invoice</p><p>Total <b>€45,20</b></p><script>USD 99</script>".utf8)
        XCTAssertEqual(ReceiptDetector.detect(ReceiptSource(html))?.money, ReceiptMoney(amount: Decimal(string: "45.20")!, currency: "EUR"))
    }
    func testReceiptUsesHTMLWhenPlainPartIsEmptyOrIncomplete() {
        let mail = message(accountID: UUID(), subject: "Thanks for shopping", body: "   ")
        mail.cachedHTML = Data("<p>Payment successful</p><p>Order total £42.00</p>".utf8)
        XCTAssertEqual(ReceiptDetector.detect(ReceiptSource(mail))?.money, ReceiptMoney(amount: 42, currency: "GBP"))
        mail.cachedText = Data("View your purchase online".utf8)
        XCTAssertEqual(ReceiptDetector.detect(ReceiptSource(mail))?.money, ReceiptMoney(amount: 42, currency: "GBP"))
    }
    func testReceiptDetectsTransactionEvidenceWithoutGenericMoneyFalsePositive() {
        let mail = message(accountID: UUID(), subject: "Shopping update", body: "Order number 882\nTotal paid GBP 17.50\nPayment method Visa")
        XCTAssertNotNil(ReceiptDetector.detect(ReceiptSource(mail)))
        mail.subject = "Weekend sale ends today"
        XCTAssertNil(ReceiptDetector.detect(ReceiptSource(mail)))
        XCTAssertNil(ReceiptDetector.detect(ReceiptSource(message(accountID: UUID(), subject: "Budget discussion", body: "We should spend £17.50"))))
    }
    func testReceiptCorrectionsPersistAndExclusionPreservesOriginal() throws {
        let container = try MailStorage.open(inMemory: true), account = MailAccount(provider: .gmail, email: "me@example.com")
        let repository = MailRepository(context: container.mainContext)
        repository.context.insert(account)
        let mail = message(accountID: account.id, subject: "Lunch", body: "")
        repository.context.insert(mail); try repository.context.save()
        let source = ReceiptSource(mail)
        var correction = ReceiptOverride(accountID: account.id, remoteID: mail.remoteID)
        correction.merchant = "Local café"; correction.money = ReceiptMoney(amount: 12, currency: "GBP"); correction.amountReviewed = true
        try repository.saveReceipt(correction)
        let saved = try ReceiptOverride.decode(XCTUnwrap(repository.metadata(correction.key)))
        XCTAssertEqual(saved, correction)
        XCTAssertEqual(saved.apply(to: source, detected: nil)?.merchant, "Local café")
        XCTAssertEqual(saved.apply(to: source, detected: nil)?.money?.amount, 12)
        correction.inclusion = "exclude"; try repository.saveReceipt(correction)
        XCTAssertNil(correction.apply(to: source, detected: ReceiptDetector.detect(source)))
        XCTAssertNotNil(try repository.message(accountID: account.id, remoteID: mail.remoteID))
        correction.money = ReceiptMoney(amount: 12, currency: "???")
        XCTAssertThrowsError(try repository.saveReceipt(correction))
    }
    func testReceiptExportQuotesCellsAndPreventsSpreadsheetFormulaInterpretation() {
        let summary = ReceiptSummary(id: UUID(), accountID: UUID(), remoteID: "m", merchant: "=HYPERLINK(\"example\")",
            kind: "Receipt", money: ReceiptMoney(amount: 12, currency: "GBP"), subject: "Paper, ink\nOrder", senderEmail: "orders@example.com", receivedAt: Date(timeIntervalSince1970: 1000))
        let csv = ReceiptExport.csv([summary])
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"example\"\")\""))
        XCTAssertTrue(csv.contains("\"Paper, ink\nOrder\""))
        XCTAssertTrue(csv.contains("\"12\",\"GBP\""))
        XCTAssertTrue(csv.contains("Detected"))
    }
}
