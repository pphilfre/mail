import Foundation
import SwiftData

struct ScheduledDelivery: Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    var retryAfter: Date?
    static func key(_ id: UUID) -> String { "scheduled-delivery:\(id.uuidString)" }
}

@MainActor extension MailRepository {
    func schedule(_ draft: LocalDraft, at date: Date, now: Date = Date()) throws {
        guard date > now, let accountID = draft.accountID, let account = try account(id: accountID),
              account.providerRaw == MailProviderKind.gmail.rawValue,
              let row = try outgoing(draft.id), row.stateRaw == "draft" else { throw GmailError.reconnect }
        guard row.lastError != "remote-draft-create-unconfirmed" else { throw GmailError.uncertainDraft }
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
    func deferScheduled(_ id: UUID, until date: Date, error: String) throws {
        guard let row = try outgoing(id), row.stateRaw == "scheduled", let saved = try metadata(ScheduledDelivery.key(id)) else { return }
        var delivery = try JSONDecoder().decode(ScheduledDelivery.self, from: Data(saved.value.utf8))
        delivery.retryAfter = date; row.lastError = error
        try setMetadata(ScheduledDelivery.key(id), value: String(decoding: try JSONEncoder().encode(delivery), as: UTF8.self))
        try context.save()
    }
    func scheduledDue(at now: Date = Date()) throws -> [OutgoingMessage] {
        try context.fetch(FetchDescriptor<OutgoingMessage>()).filter { row in
            guard row.stateRaw == "scheduled", let saved = try? self.metadata(ScheduledDelivery.key(row.id)),
                  let delivery = try? JSONDecoder().decode(ScheduledDelivery.self, from: Data(saved.value.utf8)) else { return false }
            return delivery.date <= now && (delivery.retryAfter.map { $0 <= now } ?? true)
        }
    }
}

@MainActor extension AppRuntime {
    func deliverScheduledMail() async {
        guard appLock.unlocked, connectivity.isConnected == true, let repository, let gmail else { return }
        do {
            let due = try repository.scheduledDue()
            guard !due.isEmpty else { return }
            for row in due {
                guard appLock.unlocked, row.stateRaw == "scheduled", !deliveringScheduled.contains(row.id) else { continue }
                deliveringScheduled.insert(row.id)
                defer { deliveringScheduled.remove(row.id) }
                let draft = try repository.localDraft(row)
                do {
                    try await gmail.send(draft, queued: true)
                    scheduledSentSequence += 1
                    try repository.setMetadata(ScheduledDelivery.key(row.id), value: nil)
                    try repository.context.save()
                } catch {
                    let remainsQueued = try repository.metadata(ScheduledDelivery.key(row.id)) != nil
                    if row.stateRaw == "scheduled", Self.retryablePreparation(error) {
                        try repository.deferScheduled(row.id, until: Date().addingTimeInterval(60), error: error.localizedDescription)
                    } else if row.stateRaw == "scheduled" || (row.stateRaw == "draft" && remainsQueued) {
                        row.stateRaw = "sendFailed"; row.lastError = error.localizedDescription; try repository.context.save()
                    }
                    // Sending/uncertain states are never retried automatically.
                }
            }
            try session?.reloadDrafts()
        } catch { session?.storageError = error.localizedDescription }
    }
    private static func retryablePreparation(_ error: Error) -> Bool {
        if let url = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .cancelled].contains(url.code)
        }
        if let gmail = error as? GmailError {
            if gmail == .busy { return true }
            if case .http(let status) = gmail { return status == 429 || (500..<600).contains(status) }
        }
        return false
    }
}
