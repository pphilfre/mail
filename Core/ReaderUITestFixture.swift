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
        }
        try context.save()
    }
}
#endif
