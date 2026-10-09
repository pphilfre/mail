import Foundation
import SwiftData

struct ScheduledDelivery: Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    static func key(_ id: UUID) -> String { "scheduled-delivery:\(id.uuidString)" }
}

@MainActor extension MailRepository {
    func schedule(_ draft: LocalDraft, at date: Date, now: Date = Date()) throws {
        guard date > now, let accountID = draft.accountID, let account = try account(id: accountID),
              account.providerRaw == MailProviderKind.gmail.rawValue,
              let row = try outgoing(draft.id), row.stateRaw == "draft" else { throw GmailError.reconnect }
        try context.transaction {
            let delivery = ScheduledDelivery(id: draft.id, date: date)
            try setMetadata(ScheduledDelivery.key(draft.id), value: String(decoding: try JSONEncoder().encode(delivery), as: UTF8.self))
            row.stateRaw = "scheduled"; row.lastError = nil
            try context.save()
        }
    }
    func cancelScheduled(_ id: UUID) throws {
        guard let row = try outgoing(id), ["scheduled", "sendFailed"].contains(row.stateRaw) else { throw GmailError.busy }
        try context.transaction {
            row.stateRaw = "draft"; row.lastError = nil
            try setMetadata(ScheduledDelivery.key(id), value: nil)
            try context.save()
        }
    }
    func scheduledDue(at now: Date = Date()) throws -> [OutgoingMessage] {
        try context.fetch(FetchDescriptor<OutgoingMessage>()).filter { row in
            guard row.stateRaw == "scheduled", let saved = try? self.metadata(ScheduledDelivery.key(row.id)),
                  let delivery = try? JSONDecoder().decode(ScheduledDelivery.self, from: Data(saved.value.utf8)) else { return false }
            return delivery.date <= now
        }
    }
}

@MainActor extension AppRuntime {
    func deliverScheduledMail() async {
        guard connectivity.isConnected != false, let repository, let gmail else { return }
        do {
            let due = try repository.scheduledDue()
            guard !due.isEmpty else { return }
            for row in due {
                guard row.stateRaw == "scheduled", !deliveringScheduled.contains(row.id) else { continue }
                deliveringScheduled.insert(row.id)
                defer { deliveringScheduled.remove(row.id) }
                let draft = try repository.localDraft(row)
                do {
                    try await gmail.send(draft, queued: true)
                    try repository.setMetadata(ScheduledDelivery.key(row.id), value: nil)
                    try repository.context.save()
                } catch {
                    if row.stateRaw == "scheduled" || (row.stateRaw == "draft" && error as? GmailError != .cancelled) { row.stateRaw = "sendFailed"; row.lastError = error.localizedDescription; try repository.context.save() }
                    session?.storageError = error.localizedDescription
                }
            }
            try session?.reloadDrafts()
        } catch { session?.storageError = error.localizedDescription }
    }
}
