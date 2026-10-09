import Foundation
import SwiftData

@MainActor extension MailRepository {
    func saveSecurityHeaders(_ headers: [GmailHeader], messageID: UUID) throws {
        let selected = headers.filter { ["authentication-results", "received-spf", "dkim-signature"].contains($0.name.lowercased()) }
            .prefix(30).map { GmailHeader(name: String($0.name.prefix(80)), value: String($0.value.prefix(8192))) }
        let data = try JSONEncoder().encode(selected)
        try setMetadata("security-headers:\(messageID)", value: data.base64EncodedString())
    }
    func securityHeaders(_ messageID: UUID) throws -> [GmailHeader] {
        guard let value = try metadata("security-headers:\(messageID)")?.value, let data = Data(base64Encoded: value) else { return [] }
        return try JSONDecoder().decode([GmailHeader].self, from: data)
    }
    func senderSecurityHistory(for message: MailMessage) throws -> [LocalSenderRecord] {
        let accountID = message.accountID, date = message.receivedAt
        var descriptor = FetchDescriptor<MailMessage>(predicate: #Predicate { $0.accountID == accountID && $0.receivedAt < date && !$0.isSent && !$0.isDraft && !$0.isTrash }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        descriptor.fetchLimit = 2000
        return try context.fetch(descriptor).map { LocalSenderRecord(email: $0.senderEmail, name: $0.senderName, date: $0.receivedAt, spam: $0.isSpam) }
    }
}
