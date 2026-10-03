import Foundation
import SwiftData

enum MailProviderKind: String, Codable, Sendable { case gmail, zoho }

struct MailAddress: Codable, Equatable, Hashable, Sendable {
    var name: String?
    var email: String
    var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? email }
}

/// Account credentials deliberately do not appear anywhere in the SwiftData schema.
@Model
final class MailAccount {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var identity: String
    var providerRaw: String
    var email: String
    var displayName: String
    var colourHex: String
    var dataCentre: String?
    var remoteAccountID: String?
    var historyID: String?
    var syncCursor: String?
    var lastSyncAt: Date?
    var lastSyncError: String?

    init(id: UUID = UUID(), provider: MailProviderKind, email: String, displayName: String = "") {
        self.id = id
        self.identity = "\(provider.rawValue):\(email.lowercased())"
        self.providerRaw = provider.rawValue
        self.email = email
        self.displayName = displayName.isEmpty ? email : displayName
        self.colourHex = "007AFF"
    }
}

@Model
final class MailMessage {
    #Index<MailMessage>([\.accountID, \.receivedAt], [\.receivedAt])
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var identity: String
    var accountID: UUID
    var remoteID: String
    var remoteThreadID: String
    var senderName: String?
    var senderEmail: String
    var to: [MailAddress]
    var cc: [MailAddress]
    var bcc: [MailAddress]
    var subject: String
    var snippet: String
    var receivedAt: Date
    var isRead: Bool
    var isStarred: Bool
    var isInbox: Bool
    var isSent: Bool
    var isDraft: Bool
    var isTrash: Bool
    var isSpam: Bool
    var folderIDs: [String]
    var internetMessageID: String?
    var referencesHeader: String?
    var replyTo: [MailAddress]
    @Attribute(.externalStorage) var cachedText: Data?
    @Attribute(.externalStorage) var cachedHTML: Data?

    var sender: MailAddress { MailAddress(name: senderName, email: senderEmail) }
    var plainTextBody: String? { cachedText.flatMap { String(data: $0, encoding: .utf8) } }

    init(id: UUID = UUID(), accountID: UUID, remoteID: String, remoteThreadID: String,
         sender: MailAddress, subject: String, snippet: String, receivedAt: Date) {
        self.id = id
        self.accountID = accountID
        self.remoteID = remoteID
        self.identity = "\(accountID.uuidString):\(remoteID)"
        self.remoteThreadID = remoteThreadID
        self.senderName = sender.name
        self.senderEmail = sender.email
        self.subject = subject
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.to = []; self.cc = []; self.bcc = []; self.replyTo = []
        self.isRead = false; self.isStarred = false; self.isInbox = false
        self.isSent = false; self.isDraft = false; self.isTrash = false; self.isSpam = false
        self.folderIDs = []
    }
}

@Model
final class MailThread {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var identity: String
    var accountID: UUID
    var remoteID: String
    var subject: String
    var latestMessageAt: Date

    init(accountID: UUID, remoteID: String, subject: String, latestMessageAt: Date) {
        self.id = UUID()
        self.identity = "\(accountID.uuidString):\(remoteID)"
        self.accountID = accountID
        self.remoteID = remoteID
        self.subject = subject
        self.latestMessageAt = latestMessageAt
    }
}

@Model
final class MailAttachment {
    @Attribute(.unique) var id: UUID
    var accountID: UUID
    var messageID: UUID
    var remoteID: String?
    var partID: String
    var filename: String
    var mimeType: String
    var byteCount: Int
    var contentID: String?
    var cachedRelativePath: String?

    init(accountID: UUID, messageID: UUID, partID: String, filename: String, mimeType: String, byteCount: Int) {
        self.id = UUID(); self.accountID = accountID; self.messageID = messageID
        self.partID = partID; self.filename = filename; self.mimeType = mimeType; self.byteCount = byteCount
    }
}

@Model
final class MailFolder {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var identity: String
    var accountID: UUID
    var remoteID: String
    var name: String
    var kindRaw: String
    var colourHex: String?

    init(accountID: UUID, remoteID: String, name: String, kind: String) {
        self.id = UUID(); self.identity = "\(accountID.uuidString):\(remoteID)"
        self.accountID = accountID; self.remoteID = remoteID; self.name = name; self.kindRaw = kind
    }
}

@Model
final class OutgoingMessage {
    @Attribute(.unique) var id: UUID
    var accountID: UUID?
    var toRaw: String
    var ccRaw: String
    var bccRaw: String
    var subject: String
    var body: String
    var updatedAt: Date
    var stateRaw: String
    var remoteDraftID: String?
    var remoteThreadID: String?
    var inReplyTo: String?
    var referencesHeader: String?
    var internetMessageID: String
    var lastError: String?

    init(draft: LocalDraft) {
        self.id = draft.id; self.toRaw = draft.to; self.ccRaw = draft.cc; self.bccRaw = draft.bcc
        self.subject = draft.subject; self.body = draft.body; self.updatedAt = draft.updatedAt
        self.stateRaw = "draft"
        self.accountID = draft.accountID; self.remoteThreadID = draft.remoteThreadID
        self.inReplyTo = draft.inReplyTo; self.referencesHeader = draft.referencesHeader
        self.internetMessageID = "<\(draft.id.uuidString.lowercased())@dev.freddiephilpot.dispatch>"
    }

    var localDraft: LocalDraft {
        LocalDraft(id: id, to: toRaw, cc: ccRaw, bcc: bccRaw, subject: subject, body: body, updatedAt: updatedAt,
                   accountID: accountID, remoteThreadID: remoteThreadID, inReplyTo: inReplyTo, referencesHeader: referencesHeader)
    }

    func update(from draft: LocalDraft) {
        toRaw = draft.to; ccRaw = draft.cc; bccRaw = draft.bcc
        subject = draft.subject; body = draft.body; updatedAt = draft.updatedAt
        accountID = draft.accountID; remoteThreadID = draft.remoteThreadID
        inReplyTo = draft.inReplyTo; referencesHeader = draft.referencesHeader
    }
}

@Model
final class PendingMailOperation {
    @Attribute(.unique) var id: UUID
    var accountID: UUID
    var targetRemoteID: String
    var kindRaw: String
    var createdAt: Date
    var attemptCount: Int
    var nextAttemptAt: Date?
    var lastError: String?
    var payload: Data?

    init(accountID: UUID, targetRemoteID: String, kind: String, payload: Data? = nil) {
        self.id = UUID(); self.accountID = accountID; self.targetRemoteID = targetRemoteID
        self.kindRaw = kind; self.createdAt = Date(); self.attemptCount = 0; self.payload = payload
    }
}

@Model
final class StoreMetadata {
    @Attribute(.unique) var key: String
    var value: String
    init(key: String, value: String) { self.key = key; self.value = value }
}
