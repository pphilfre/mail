import Foundation
import SwiftData

enum DraftLinks {
    static func prefix(_ accountID: UUID) -> String { "gmail-draft-link:\(accountID.uuidString):" }
    static func key(_ accountID: UUID, _ draftID: String) -> String { prefix(accountID) + draftID }
    @MainActor static func hiddenMessageIDs(outgoing: [OutgoingMessage], links: [StoreMetadata], accountID: UUID?) -> Set<String> {
        let byKey = Dictionary(uniqueKeysWithValues: links.map { ($0.key, $0.value) })
        return Set(outgoing.filter { $0.stateRaw == "draft" && (accountID == nil || $0.accountID == accountID) }.compactMap { row in
            guard let id = row.accountID, let remote = row.remoteDraftID, let messageID = byKey[key(id, remote)] else { return nil }
            return "\(id.uuidString):\(messageID)"
        })
    }
}

@MainActor extension MailRepository {
    func saveDraftLink(accountID: UUID, draftID: String, messageID: String) throws {
        let key = DraftLinks.key(accountID, draftID)
        if let row = try context.fetch(FetchDescriptor<StoreMetadata>(predicate: #Predicate { $0.key == key })).first { row.value = messageID }
        else { context.insert(StoreMetadata(key: key, value: messageID)) }
        try context.save()
    }
    func replaceDraftLinks(_ references: [GmailDraftDTO], accountID: UUID) throws {
        guard try account(id: accountID) != nil else { throw GmailError.reconnect }
        try context.transaction {
            for row in try context.fetch(FetchDescriptor<StoreMetadata>()) where row.key.hasPrefix(DraftLinks.prefix(accountID)) { context.delete(row) }
            for reference in references {
                if let id = reference.message?.id { context.insert(StoreMetadata(key: DraftLinks.key(accountID, reference.id), value: id)) }
            }
            try context.save()
        }
    }
}
