#if DEBUG
import Foundation
import SwiftData

@MainActor
enum ReaderUITestFixture {
    static var enabled: Bool { ProcessInfo.processInfo.environment["DISPATCH_UI_TEST_READER"] == "YES" }
    static func seed(_ context: ModelContext) throws {
        let account = MailAccount(provider: .gmail, email: "reader-test@example.com")
        context.insert(account)
        for (index, id) in ["earlier", "latest"].enumerated() {
            let message = MailMessage(accountID: account.id, remoteID: id, remoteThreadID: "fixture-thread",
                sender: MailAddress(name: index == 0 ? "Earlier sender" : "Latest sender", email: "reader-fixture@gmail.com"),
                subject: "Conversation layout test", snippet: "Preview \(id)", receivedAt: Date(timeIntervalSince1970: Double(1000 + index)))
            message.to = [MailAddress(name: "Me", email: account.email), MailAddress(name: "Alex", email: "alex@example.com")]
            message.cachedText = Data("\(id == "earlier" ? "Earlier" : "Latest") message body".utf8)
            message.isInbox = true; message.isRead = true; message.folderIDs = ["INBOX"]
            context.insert(message)
            if id == "latest" && ProcessInfo.processInfo.environment["DISPATCH_UI_TEST_LIBRARY"] == "YES" {
                context.insert(MailAttachment(accountID: account.id, messageID: message.id, partID: "1",
                    filename: "Project plans.pdf", mimeType: "application/pdf", byteCount: 1234))
                let logo = MailAttachment(accountID: account.id, messageID: message.id, partID: "2",
                    filename: "Inline logo.png", mimeType: "image/png", byteCount: 100)
                logo.contentID = "logo-fixture"; context.insert(logo)
            }
        }
        if ProcessInfo.processInfo.environment["DISPATCH_UI_TEST_PRODUCTIVITY"] == "YES" {
            let receipt = MailMessage(accountID: account.id, remoteID: "receipt-fixture", remoteThreadID: "receipt-thread",
                sender: MailAddress(name: "Paper & Ink", email: "receipts@example.com"),
                subject: "Your receipt from Paper & Ink", snippet: "Order total £22.00", receivedAt: Date())
            receipt.cachedText = Data("Receipt from Paper & Ink\nSubtotal £19.00\nTax £3.00\nOrder total £22.00\nOrder #0008".utf8)
            receipt.isInbox = true; receipt.isRead = true; receipt.folderIDs = ["INBOX"]
            context.insert(receipt)
        }
        if ProcessInfo.processInfo.environment["DISPATCH_UI_TEST_SUBSCRIPTIONS"] == "YES" {
            let newsletter = MailMessage(accountID: account.id, remoteID: "newsletter-fixture", remoteThreadID: "newsletter-thread",
                sender: MailAddress(name: "Daily Dispatch", email: "news@example.com"), subject: "Your weekly newsletter",
                snippet: "This week's stories", receivedAt: Date())
            newsletter.cachedText = Data("Weekly news\nManage your email preferences or unsubscribe".utf8)
            newsletter.isInbox = true; newsletter.folderIDs = ["INBOX", "UNREAD"]
            context.insert(newsletter)
        }
        try context.save()
    }
}
#endif
