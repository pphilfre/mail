import Foundation
import SwiftData

enum DraftAttachments {
    static func key(_ id: UUID) -> String { "draft-attachments:\(id.uuidString)" }
    static func revisionKey(_ id: UUID) -> String { "draft-owned-revision:\(id.uuidString)" }
}

@MainActor extension MailRepository {
    func localDraft(_ row: OutgoingMessage) throws -> LocalDraft {
        var draft = row.localDraft
        if let value = try metadata(DraftAttachments.key(row.id))?.value {
            draft.attachments = try JSONDecoder().decode([DraftAttachment].self, from: Data(value.utf8))
        }
        return draft
    }
    func metadata(_ key: String) throws -> StoreMetadata? {
        try context.fetch(FetchDescriptor<StoreMetadata>(predicate: #Predicate { $0.key == key })).first
    }
    func setMetadata(_ key: String, value: String?) throws {
        let existing = try metadata(key)
        if let value {
            if let existing { existing.value = value }
            else { context.insert(StoreMetadata(key: key, value: value)) }
        } else if let existing { context.delete(existing) }
    }
    func saveAttachments(_ draft: LocalDraft) throws {
        try DraftAttachmentStore.validate(draft.attachments)
        let value = draft.attachments.isEmpty ? nil : String(decoding: try JSONEncoder().encode(draft.attachments), as: UTF8.self)
        try setMetadata(DraftAttachments.key(draft.id), value: value)
    }
    func removeDraftMetadata(_ id: UUID) throws {
        try setMetadata(DraftAttachments.key(id), value: nil)
        try setMetadata(DraftAttachments.revisionKey(id), value: nil)
    }
    /// Gmail replaces the immutable message ID on every draft edit. A refresh of the
    /// mailbox link must never replace this acknowledgement of our own last write.
    func canReplaceDraft(_ remote: GmailDraftDTO, row: OutgoingMessage) throws -> Bool {
        if let revision = try metadata(DraftAttachments.revisionKey(row.id))?.value {
            return row.remoteDraftID == remote.id && remote.message?.id == revision
        }
        return MailMIME.canEditDraft(remote.message?.payload)
    }
    func acknowledgeDraft(_ remote: GmailDraftDTO, row: OutgoingMessage) throws {
        try context.transaction {
            row.remoteDraftID = remote.id; row.lastError = nil
            try setMetadata(DraftAttachments.revisionKey(row.id), value: remote.message?.id)
            if let messageID = remote.message?.id, let accountID = row.accountID {
                let key = DraftLinks.key(accountID, remote.id)
                try setMetadata(key, value: messageID)
            }
            try context.save()
        }
    }
}
