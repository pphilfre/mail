import Foundation
import SwiftData

struct MailOrganisationRule: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var revision = UUID()
    var name = ""
    var sender = ""
    var subject = ""
    var accountID: UUID?
    var action = "read"
    var enabled = true
    var key: String { "mail-rule:\(id.uuidString)" }
    @MainActor func matches(_ message: MailMessage) -> Bool {
        enabled && !message.isSent && !message.isDraft && !message.isSpam && !message.isTrash &&
            (accountID == nil || accountID == message.accountID) &&
            (!sender.isEmpty || !subject.isEmpty) &&
            (sender.isEmpty || message.senderEmail.localizedCaseInsensitiveContains(sender)) &&
            (subject.isEmpty || message.subject.localizedCaseInsensitiveContains(subject))
    }
    static func decode(_ row: StoreMetadata) -> Self? {
        guard let value = try? JSONDecoder().decode(Self.self, from: Data(row.value.utf8)), value.key == row.key else { return nil }
        return value
    }
}

@MainActor extension MailRepository {
    func applyRules(to messages: [MailMessage]) throws {
        let rules = try context.fetch(FetchDescriptor<StoreMetadata>()).compactMap(MailOrganisationRule.decode)
        for message in messages {
            for rule in rules where rule.matches(message) {
                guard ["archive", "read", "star"].contains(rule.action) else { continue }
                let marker = "mail-rule-applied:\(message.identity):\(rule.id)"
                guard try metadata(marker)?.value != rule.revision.uuidString else { continue }
                context.insert(PendingMailOperation(accountID: message.accountID, targetRemoteID: message.remoteID, kind: rule.action))
                Self.overlay(rule.action, on: message)
                try setMetadata(marker, value: rule.revision.uuidString)
            }
        }
    }
    func saveRule(_ rule: MailOrganisationRule) throws {
        guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !rule.sender.isEmpty || !rule.subject.isEmpty else { throw GmailError.invalidResponse }
        try setMetadata(rule.key, value: String(decoding: try JSONEncoder().encode(rule), as: UTF8.self))
        try context.save()
    }
}
