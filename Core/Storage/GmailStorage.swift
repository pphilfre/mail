import Foundation
import SwiftData

@MainActor
extension MailRepository {
    func apply(_ dtos: [GmailMessageDTO], deleted: Set<String> = [], accountID: UUID, historyID: String? = nil) throws {
        guard try account(id: accountID) != nil else { throw GmailError.reconnect }
        try context.transaction {
            let pending = try context.fetch(FetchDescriptor<PendingMailOperation>(predicate: #Predicate { $0.accountID == accountID },
                sortBy: [SortDescriptor(\.createdAt)]))
            for remoteID in deleted {
                if let row = try message(accountID: accountID, remoteID: remoteID) {
                    let id = row.id
                    try context.delete(model: MailAttachment.self, where: #Predicate { $0.messageID == id })
                    try setMetadata("security-headers:\(id)", value: nil)
                    context.delete(row)
                }
            }
            for dto in dtos {
                let payload = dto.payload
                let from = MailMIME.addresses(payload?.header("From") ?? "").first ?? MailAddress(name: nil, email: "Unknown sender")
                let date = Date(timeIntervalSince1970: (Double(dto.internalDate ?? "") ?? 0) / 1000)
                let row = try message(accountID: accountID, remoteID: dto.id) ?? MailMessage(accountID: accountID,
                    remoteID: dto.id, remoteThreadID: dto.threadId, sender: from, subject: "", snippet: "", receivedAt: date)
                if row.modelContext == nil { context.insert(row) }
                row.senderName = from.name; row.senderEmail = from.email; row.remoteThreadID = dto.threadId
                row.receivedAt = date; row.subject = MailMIME.decodedHeader(payload?.header("Subject") ?? "")
                row.snippet = MailMIME.readableHTML(dto.snippet ?? "")
                row.to = MailMIME.addresses(payload?.header("To") ?? ""); row.cc = MailMIME.addresses(payload?.header("Cc") ?? "")
                row.bcc = MailMIME.addresses(payload?.header("Bcc") ?? ""); row.replyTo = MailMIME.addresses(payload?.header("Reply-To") ?? "")
                if let header = payload?.header("List-Unsubscribe") {
                    let value = MailUnsubscribe(header: header, post: payload?.header("List-Unsubscribe-Post") ?? "",
                        signature: payload?.header("DKIM-Signature") ?? "", authentication: payload?.header("Authentication-Results") ?? "")
                    try setMetadata(MailUnsubscribe.key(row), value: String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
                } else { try setMetadata(MailUnsubscribe.key(row), value: nil) }
                row.internetMessageID = payload?.header("Message-ID"); row.referencesHeader = payload?.header("References")
                try saveSecurityHeaders(payload?.headers ?? [], messageID: row.id)
                row.folderIDs = dto.labelIds ?? []
                for operation in pending where operation.targetRemoteID == dto.id { Self.overlay(operation.kindRaw, on: row) }
                Self.flags(row)
                let content = MailMIME.content(payload)
                row.cachedText = content.text.isEmpty ? nil : Data(content.text.utf8)
                row.cachedHTML = content.html.isEmpty ? nil : Data(content.html.utf8)
                let messageID = row.id
                let existingAttachments = try context.fetch(FetchDescriptor<MailAttachment>(predicate: #Predicate { $0.messageID == messageID }))
                var retained = Set<UUID>()
                for part in content.attachments {
                    let filename = MailMIME.decodedHeader(part.filename ?? "Attachment")
                    let attachment = existingAttachments.first { $0.remoteID != nil && !retained.contains($0.id) && $0.partID == (part.partId ?? "") &&
                        $0.remoteID == part.body?.attachmentId && $0.filename == filename && $0.byteCount == (part.body?.size ?? 0) &&
                        $0.mimeType == (part.mimeType ?? "application/octet-stream") } ??
                        MailAttachment(accountID: accountID, messageID: row.id, partID: part.partId ?? "",
                        filename: MailMIME.decodedHeader(part.filename ?? "Attachment"), mimeType: part.mimeType ?? "application/octet-stream",
                        byteCount: part.body?.size ?? 0)
                    attachment.remoteID = part.body?.attachmentId; attachment.contentID = part.header("Content-ID")
                    if attachment.modelContext == nil { context.insert(attachment) }
                    retained.insert(attachment.id)
                }
                for attachment in existingAttachments where !retained.contains(attachment.id) { context.delete(attachment) }
                let identity = "\(accountID.uuidString):\(dto.threadId)"
                let thread = try context.fetch(FetchDescriptor<MailThread>(predicate: #Predicate { $0.identity == identity })).first
                if let thread {
                    if date >= thread.latestMessageAt { thread.subject = row.subject; thread.latestMessageAt = date }
                } else { context.insert(MailThread(accountID: accountID, remoteID: dto.threadId, subject: row.subject, latestMessageAt: date)) }
            }
            let ruleMessages = try dtos.compactMap { try message(accountID: accountID, remoteID: $0.id) }
            try applyRules(to: ruleMessages)
            if let historyID, let account = try account(id: accountID) { account.historyID = historyID }
            try context.save()
        }
    }
    static func flags(_ row: MailMessage) {
        let labels = Set(row.folderIDs)
        row.isRead = !labels.contains("UNREAD"); row.isStarred = labels.contains("STARRED")
        row.isInbox = labels.contains("INBOX"); row.isSent = labels.contains("SENT")
        row.isDraft = labels.contains("DRAFT"); row.isTrash = labels.contains("TRASH"); row.isSpam = labels.contains("SPAM")
    }
    static func overlay(_ kind: String, on row: MailMessage) {
        var labels = Set(row.folderIDs)
        switch kind {
        case "read": labels.remove("UNREAD")
        case "unread": labels.insert("UNREAD")
        case "star": labels.insert("STARRED")
        case "unstar": labels.remove("STARRED")
        case "archive": labels.remove("INBOX")
        case "trash": labels.insert("TRASH"); labels.remove("INBOX")
        case "restore": labels.remove("TRASH")
        case "spam": labels.insert("SPAM"); labels.remove("INBOX")
        case "notSpam": labels.remove("SPAM"); labels.insert("INBOX")
        default:
            if kind.hasPrefix("labelAdd:") { labels.insert(String(kind.dropFirst(9))) }
            if kind.hasPrefix("labelRemove:") { labels.remove(String(kind.dropFirst(12))) }
            if kind.hasPrefix("move:") { labels.insert(String(kind.dropFirst(5))); labels.remove("INBOX") }
        }
        row.folderIDs = labels.sorted(); flags(row)
    }
    func enqueue(_ kind: String, message: MailMessage) throws {
        _ = try enqueueBatch(kind, messages: [message])
    }
    func saveLabels(_ labels: [GmailLabel], accountID: UUID) throws {
        try context.transaction {
            try context.delete(model: MailFolder.self, where: #Predicate { $0.accountID == accountID })
            for label in labels { context.insert(MailFolder(accountID: accountID, remoteID: label.id, name: label.name, kind: label.type ?? "user")) }
            try context.save()
        }
    }
    func outgoing(_ id: UUID) throws -> OutgoingMessage? {
        try context.fetch(FetchDescriptor<OutgoingMessage>(predicate: #Predicate { $0.id == id })).first
    }
    func recoverInterruptedSends() throws {
        for row in try context.fetch(FetchDescriptor<OutgoingMessage>(predicate: #Predicate { $0.stateRaw == "sending" })) {
            row.stateRaw = "sendUnconfirmed"; row.lastError = GmailError.uncertainSend.localizedDescription
        }
        try context.save()
    }
}
