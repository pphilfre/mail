import Foundation
import SwiftData

/// Device-local organisation, independent of provider labels and credentials.
struct MailLocalOrganisation: Codable, Equatable, Sendable {
    var pinned = false
    var snoozedUntil: Date?
    func isSnoozed(at date: Date) -> Bool { snoozedUntil.map { $0 > date } ?? false }
    @MainActor static func key(_ message: MailMessage) -> String {
        let target = message.remoteThreadID.isEmpty ? "message:\(message.remoteID)" : "thread:\(message.remoteThreadID)"
        return "mail-organisation:\(message.accountID.uuidString):\(target)"
    }
    @MainActor static func values(_ metadata: [StoreMetadata]) -> [String: Self] {
        metadata.reduce(into: [:]) { result, row in
            if row.key.hasPrefix("mail-organisation:"), let value = try? JSONDecoder().decode(Self.self, from: Data(row.value.utf8)) { result[row.key] = value }
        }
    }
}

@MainActor extension MailRepository {
    func organise(_ message: MailMessage, pinned: Bool? = nil, snoozedUntil: Date? = nil, clearSnooze: Bool = false) throws {
        guard try account(id: message.accountID) != nil else { throw GmailError.reconnect }
        let key = MailLocalOrganisation.key(message)
        var value = try metadata(key).flatMap { try? JSONDecoder().decode(MailLocalOrganisation.self, from: Data($0.value.utf8)) } ?? MailLocalOrganisation()
        if let pinned { value.pinned = pinned }
        if clearSnooze { value.snoozedUntil = nil }
        else if let snoozedUntil { value.snoozedUntil = snoozedUntil }
        try context.transaction {
            try setMetadata(key, value: String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
            try context.save()
        }
    }
}
