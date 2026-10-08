import Foundation
import SwiftData

@MainActor
protocol DraftPersistence {
    func load() throws -> [LocalDraft]
    func save(_ drafts: [LocalDraft]) throws
}

/// Main-actor access keeps SwiftData models out of provider actors and network tasks.
/// Foreign-key UUIDs are explicit; account removal deletes all associated rows atomically.
@MainActor
final class MailRepository: DraftPersistence {
    let context: ModelContext
    init(context: ModelContext) { self.context = context; context.autosaveEnabled = false }

    func load() throws -> [LocalDraft] {
        let descriptor = FetchDescriptor<OutgoingMessage>(
            predicate: #Predicate { $0.stateRaw == "draft" },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { try localDraft($0) }
    }

    func save(_ drafts: [LocalDraft]) throws {
        try context.transaction {
            // A stale composer/session must never resurrect a sent or uncertain message by UUID.
            for draft in drafts {
                if let row = try outgoing(draft.id), row.stateRaw != "draft" { throw GmailError.uncertainSend }
            }
            let existing = try context.fetch(FetchDescriptor<OutgoingMessage>(predicate: #Predicate { $0.stateRaw == "draft" }))
            let incomingIDs = Set(drafts.map(\.id))
            let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            for row in existing where !incomingIDs.contains(row.id) {
                try removeDraftMetadata(row.id); context.delete(row)
            }
            for draft in drafts {
                if let row = byID[draft.id] {
                    if row.accountID != draft.accountID { try setMetadata(DraftAttachments.revisionKey(row.id), value: nil) }
                    row.update(from: draft)
                }
                else { context.insert(OutgoingMessage(draft: draft)) }
                try saveAttachments(draft)
            }
            try context.save()
        }
    }

    func migrateFoundationDrafts(from legacy: DraftStore) throws {
        let marker = "foundation-drafts-v1-imported"
        var descriptor = FetchDescriptor<StoreMetadata>(predicate: #Predicate { $0.key == marker })
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        // Read before any mutation. Unreadable legacy files are never replaced or silently discarded.
        let drafts = try legacy.load()
        try context.transaction {
            let existing = Set(try context.fetch(FetchDescriptor<OutgoingMessage>()).map(\.id))
            for draft in drafts where !existing.contains(draft.id) {
                context.insert(OutgoingMessage(draft: draft)); try saveAttachments(draft)
            }
            context.insert(StoreMetadata(key: marker, value: "complete"))
            try context.save()
        }
        // Keep the protected legacy file for recovery; the durable marker prevents resurrection.
    }

    func accounts() throws -> [MailAccount] {
        try context.fetch(FetchDescriptor<MailAccount>(sortBy: [SortDescriptor(\.email)]))
    }

    func account(id: UUID) throws -> MailAccount? {
        var descriptor = FetchDescriptor<MailAccount>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func message(accountID: UUID, remoteID: String) throws -> MailMessage? {
        let identity = "\(accountID.uuidString):\(remoteID)"
        var descriptor = FetchDescriptor<MailMessage>(predicate: #Predicate { $0.identity == identity })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func recentMessages(accountID: UUID? = nil, limit: Int = 100) throws -> [MailMessage] {
        var descriptor = FetchDescriptor<MailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        if let accountID { descriptor.predicate = #Predicate { $0.accountID == accountID } }
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func removeAccountData(id: UUID) throws {
        try context.transaction {
            try removeSenderProfileAccount(id)
            try removeCollectionAccount(id)
            for row in try context.fetch(FetchDescriptor<OutgoingMessage>(predicate: #Predicate { $0.accountID == id })) {
                try removeDraftMetadata(row.id)
            }
            // Undo can span accounts; remove the whole record rather than retaining deleted identities.
            if let undo = try context.fetch(FetchDescriptor<StoreMetadata>(predicate: #Predicate { $0.key == "mail-triage-undo" })).first {
                context.delete(undo)
            }
            for metadata in try context.fetch(FetchDescriptor<StoreMetadata>())
                where metadata.key.hasPrefix(GmailMailbox.pagePrefix(id)) || metadata.key.hasPrefix(DraftLinks.prefix(id)) ||
                    metadata.key.hasPrefix(MailTask.prefix(id)) || metadata.key.hasPrefix(ReceiptOverride.prefix(id)) ||
                    metadata.key.hasPrefix(SubscriptionRule.prefix(id)) ||
                    metadata.key.hasPrefix("mail-organisation:\(id.uuidString):") { context.delete(metadata) }
            try context.delete(model: MailAttachment.self, where: #Predicate { $0.accountID == id })
            try context.delete(model: PendingMailOperation.self, where: #Predicate { $0.accountID == id })
            try context.delete(model: OutgoingMessage.self, where: #Predicate { $0.accountID == id })
            try context.delete(model: MailMessage.self, where: #Predicate { $0.accountID == id })
            try context.delete(model: MailThread.self, where: #Predicate { $0.accountID == id })
            try context.delete(model: MailFolder.self, where: #Predicate { $0.accountID == id })
            try context.delete(model: MailAccount.self, where: #Predicate { $0.id == id })
            try context.save()
        }
    }
}
