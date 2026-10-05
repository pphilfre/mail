import Foundation
import SwiftData

struct SubscriptionRule: Codable, Equatable, Sendable {
    var version = 1
    let accountID: UUID
    let email: String
    var included: Bool
    static func prefix(_ accountID: UUID) -> String { "subscription-rule:\(accountID.uuidString):" }
    var key: String { Self.prefix(accountID) + email }
    static func decode(_ row: StoreMetadata) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: Data(row.value.utf8))
        guard value.version == 1, value.key == row.key, MailMIME.valid(value.email),
              value.email == value.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { throw SubscriptionRuleError.invalidData }
        return value
    }
}

enum SubscriptionRuleError: LocalizedError {
    case invalidData
    var errorDescription: String? { "A saved newsletter choice could not be read. Its saved data has been kept." }
}

@MainActor extension MailRepository {
    func setSubscription(email: String, included: Bool?, accountIDs: Set<UUID>) throws {
        let email = SenderInsights.normalise(email), available = Set(try accounts().map(\.id))
        guard MailMIME.valid(email), !accountIDs.isEmpty, accountIDs.isSubset(of: available) else { throw GmailError.reconnect }
        try context.transaction {
            for accountID in accountIDs {
                let key = SubscriptionRule.prefix(accountID) + email
                if let row = try metadata(key) { _ = try SubscriptionRule.decode(row) }
                if let included {
                    let rule = SubscriptionRule(accountID: accountID, email: email, included: included)
                    try setMetadata(key, value: String(decoding: try JSONEncoder().encode(rule), as: UTF8.self))
                } else { try setMetadata(key, value: nil) }
            }
            try context.save()
        }
    }
}
