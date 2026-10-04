import Foundation

/// Projection stays account-scoped, even when providers reuse thread identifiers.
@MainActor
struct MailConversation: Identifiable {
    let id: String
    let messages: [MailMessage]
    var latest: MailMessage { messages[0] }
    var isRead: Bool { messages.allSatisfy(\.isRead) }
    var isStarred: Bool { messages.contains(where: \.isStarred) }

    static func rows(_ messages: [MailMessage], grouped: Bool) -> [MailConversation] {
        let sorted = messages.sorted {
            if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
            return $0.identity < $1.identity
        }
        var order: [String] = []
        var groups: [String: [MailMessage]] = [:]
        for message in sorted {
            let key = grouped && !message.remoteThreadID.isEmpty && !message.isDraft
                ? "\(message.accountID):thread:\(message.remoteThreadID)" : message.identity
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(message)
        }
        return order.map { MailConversation(id: $0, messages: groups[$0] ?? []) }
    }
}

enum MailboxScope {
    static let names = ["Inbox", "All Mail", "Unread", "Starred", "Sent", "Drafts", "Archive", "Spam", "Trash"]
    @MainActor static func contains(_ row: MailMessage, mailbox: String, labelID: String? = nil) -> Bool {
        if let labelID { return row.folderIDs.contains(labelID) }
        switch mailbox {
        case "Trash": return row.isTrash
        case "Spam": return row.isSpam && !row.isTrash
        case "All Mail": return !row.isTrash && !row.isSpam
        case "Unread": return !row.isRead && !row.isTrash && !row.isSpam
        case "Starred": return row.isStarred && !row.isTrash && !row.isSpam
        case "Sent": return row.isSent && !row.isTrash && !row.isSpam
        case "Drafts": return row.isDraft && !row.isTrash && !row.isSpam
        case "Archive": return !row.isInbox && !row.isSent && !row.isDraft && !row.isTrash && !row.isSpam
        default: return row.isInbox && !row.isTrash && !row.isSpam
        }
    }
}
