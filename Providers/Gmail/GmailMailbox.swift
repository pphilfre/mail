import Foundation
import SwiftData

struct GmailMailbox: Sendable {
    let name: String
    var labelID: String?

    var parameters: (label: String?, query: String?) {
        if let labelID { return (labelID, nil) }
        switch name {
        case "Inbox": return ("INBOX", nil)
        case "Unread": return ("UNREAD", nil)
        case "Starred": return ("STARRED", nil)
        case "Sent": return ("SENT", nil)
        case "Drafts": return ("DRAFT", nil)
        case "Trash": return ("TRASH", nil)
        case "Spam": return ("SPAM", nil)
        case "Archive": return (nil, "-in:inbox -in:sent -in:drafts -in:trash -in:spam")
        default: return (nil, nil)
        }
    }

    static func pagePrefix(_ accountID: UUID) -> String { "gmail-page:\(accountID.uuidString):" }
    func pageKey(_ accountID: UUID) -> String {
        let scope = labelID.map { "label:\($0)" } ?? "mailbox:\(name)"
        return Self.pagePrefix(accountID) + Base64URL.encode(Data(scope.utf8))
    }
}

@MainActor
extension MailRepository {
    func gmailPageTokens() throws -> [String: String] {
        let metadata = try context.fetch(FetchDescriptor<StoreMetadata>()).filter { $0.key.hasPrefix("gmail-page:") }
        var tokens = Dictionary(uniqueKeysWithValues: metadata.map { ($0.key, $0.value) })
        // Preserve the existing All Mail cursor when upgrading without a database migration.
        for account in try accounts() {
            let key = GmailMailbox(name: "All Mail").pageKey(account.id)
            if tokens[key] == nil { tokens[key] = account.syncCursor }
        }
        return tokens
    }

    func saveGmailPageToken(_ token: String?, mailbox: GmailMailbox, accountID: UUID) throws {
        let key = mailbox.pageKey(accountID)
        try context.transaction {
            guard let account = try account(id: accountID) else { throw GmailError.reconnect }
            let existing = try context.fetch(FetchDescriptor<StoreMetadata>(predicate: #Predicate { $0.key == key })).first
            if let token {
                if let existing { existing.value = token }
                else { context.insert(StoreMetadata(key: key, value: token)) }
            } else if let existing { context.delete(existing) }
            if mailbox.labelID == nil && mailbox.name == "All Mail" { account.syncCursor = token }
            try context.save()
        }
    }
}
