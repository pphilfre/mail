import Foundation
import SwiftData

struct SenderProfile: Codable, Equatable, Sendable {
    var version = 1
    let email: String
    var nickname = ""
    var notes = ""
    var accountIDs: [UUID]
    static let prefix = "sender-profile:"
    var key: String { Self.prefix + email }
    static func decode(_ row: StoreMetadata) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: Data(row.value.utf8))
        guard value.version == 1, value.email == value.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              MailMIME.valid(value.email), value.key == row.key else { throw SenderProfileError.invalidData }
        return value
    }
}

enum SenderProfileError: LocalizedError {
    case invalidData
    var errorDescription: String? { "This sender profile could not be read. Its saved notes have been kept." }
}

@MainActor extension MailRepository {
    func saveSenderProfile(_ profile: SenderProfile) throws {
        guard profile.version == 1, profile.email == SenderInsights.normalise(profile.email), MailMIME.valid(profile.email) else { throw SenderProfileError.invalidData }
        if let existing = try metadata(profile.key) { _ = try SenderProfile.decode(existing) }
        var profile = profile
        let available = Set(try accounts().map(\.id))
        profile.accountIDs = Array(Set(profile.accountIDs).intersection(available)).sorted { $0.uuidString < $1.uuidString }
        guard !profile.accountIDs.isEmpty else { throw GmailError.reconnect }
        profile.nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.transaction {
            try setMetadata(profile.key, value: String(decoding: try JSONEncoder().encode(profile), as: UTF8.self))
            try context.save()
        }
    }
    func removeSenderProfileAccount(_ accountID: UUID) throws {
        for row in try context.fetch(FetchDescriptor<StoreMetadata>()) where row.key.hasPrefix(SenderProfile.prefix) {
            var profile = try SenderProfile.decode(row)
            guard profile.accountIDs.contains(accountID) else { continue }
            profile.accountIDs.removeAll { $0 == accountID }
            if profile.accountIDs.isEmpty { context.delete(row) }
            else { row.value = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self) }
        }
    }
}
