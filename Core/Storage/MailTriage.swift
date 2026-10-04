import Foundation
import SwiftData

struct MailUndoChange: Codable, Sendable {
    let accountID: UUID
    let remoteID: String
    let kinds: [String]
}

struct MailUndoRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let count: Int
    let expiresAt: Date
    let changes: [MailUndoChange]
    static let key = "mail-triage-undo"
}

@MainActor extension MailRepository {
    /// One durable transaction over a fixed message snapshot, followed by provider sync.
    @discardableResult func enqueueBatch(_ kind: String, messages: [MailMessage], now: Date = Date()) throws -> MailUndoRecord? {
        var record: MailUndoRecord?
        try context.transaction {
            var seen = Set<UUID>()
            var changes: [MailUndoChange] = []
            let base = try operationDate(now)
            for message in messages where seen.insert(message.id).inserted {
                guard try account(id: message.accountID) != nil, message.modelContext != nil else { throw GmailError.reconnect }
                let before = Set(message.folderIDs)
                Self.overlay(kind, on: message)
                let after = Set(message.folderIDs)
                guard before != after else { continue }
                let inverse = (after.subtracting(before).sorted().map { $0 == "TRASH" ? "restore" : "labelRemove:" + $0 }) +
                    before.subtracting(after).sorted().map { $0 == "TRASH" ? "trash" : "labelAdd:" + $0 }
                changes.append(MailUndoChange(accountID: message.accountID, remoteID: message.remoteID, kinds: inverse))
                let operation = PendingMailOperation(accountID: message.accountID, targetRemoteID: message.remoteID, kind: kind)
                operation.createdAt = base.addingTimeInterval(Double(changes.count) / 1000)
                context.insert(operation)
            }
            let existing = try context.fetch(FetchDescriptor<StoreMetadata>(predicate: #Predicate { $0.key == "mail-triage-undo" })).first
            if let existing { context.delete(existing) }
            if !changes.isEmpty {
                let next = MailUndoRecord(id: UUID(), title: kind, count: changes.count, expiresAt: now.addingTimeInterval(10), changes: changes)
                let value = String(decoding: try JSONEncoder().encode(next), as: UTF8.self)
                context.insert(StoreMetadata(key: MailUndoRecord.key, value: value)); record = next
            }
            try context.save()
        }
        return record
    }

    private func operationDate(_ now: Date) throws -> Date {
        var descriptor = FetchDescriptor<PendingMailOperation>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return max(now, (try context.fetch(descriptor).first?.createdAt ?? .distantPast).addingTimeInterval(0.001))
    }

    /// Compensating operations follow the originals even if a request is already in flight.
    /// Only labels changed by this action are restored; unrelated sync changes survive.
    func undoTriage(_ id: UUID, now: Date = Date()) throws -> Set<UUID> {
        var accountIDs = Set<UUID>()
        try context.transaction {
            guard let metadata = try context.fetch(FetchDescriptor<StoreMetadata>(predicate: #Predicate { $0.key == "mail-triage-undo" })).first,
                  let record = try? JSONDecoder().decode(MailUndoRecord.self, from: Data(metadata.value.utf8)),
                  record.id == id, record.expiresAt > now else { return }
            let base = try operationDate(now)
            var offset = 0
            for change in record.changes {
                guard let message = try message(accountID: change.accountID, remoteID: change.remoteID) else { continue }
                for kind in change.kinds {
                    Self.overlay(kind, on: message)
                    let operation = PendingMailOperation(accountID: change.accountID, targetRemoteID: change.remoteID, kind: kind)
                    offset += 1; operation.createdAt = base.addingTimeInterval(Double(offset) / 1000)
                    context.insert(operation)
                }
                accountIDs.insert(change.accountID)
            }
            context.delete(metadata); try context.save()
        }
        return accountIDs
    }
}
