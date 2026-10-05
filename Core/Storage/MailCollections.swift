import Foundation
import SwiftData

struct MailCollectionLink: Codable, Hashable, Identifiable, Sendable {
    let accountID: UUID
    let remoteMessageID: String
    let remoteThreadID: String
    var id: String { "\(accountID.uuidString):" + (remoteThreadID.isEmpty ? "message:\(remoteMessageID)" : "thread:\(remoteThreadID)") }
    @MainActor init(_ message: MailMessage) {
        accountID = message.accountID; remoteMessageID = message.remoteID; remoteThreadID = message.remoteThreadID
    }
    @MainActor func contains(_ message: MailMessage) -> Bool {
        accountID == message.accountID && (remoteMessageID == message.remoteID ||
            (!remoteThreadID.isEmpty && remoteThreadID == message.remoteThreadID))
    }
}

struct MailCollection: Codable, Equatable, Identifiable, Sendable {
    var version = 1
    var id = UUID()
    var name: String
    var notes = ""
    var links: [MailCollectionLink] = []
    var updatedAt = Date()
    static let prefix = "mail-collection:"
    var key: String { Self.prefix + id.uuidString }
    static func decode(_ row: StoreMetadata) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: Data(row.value.utf8))
        guard value.version == 1, value.key == row.key else { throw MailCollectionError.invalidData }
        return value
    }
    @MainActor func messages(in messages: [MailMessage], accountID: UUID?) -> [MailMessage] {
        messages.filter { message in
            !message.isDraft && !message.isTrash && !message.isSpam && (accountID == nil || message.accountID == accountID) &&
                links.contains { $0.contains(message) }
        }
    }
}

enum MailCollectionError: LocalizedError {
    case invalidData, emptyName
    var errorDescription: String? {
        switch self {
        case .invalidData: "This collection could not be read. Its saved data has been kept."
        case .emptyName: "Give this collection a name."
        }
    }
}

@MainActor extension MailRepository {
    func saveCollection(_ collection: MailCollection) throws {
        guard collection.version == 1 else { throw MailCollectionError.invalidData }
        if let existing = try metadata(collection.key) { _ = try MailCollection.decode(existing) }
        var collection = collection
        collection.name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collection.name.isEmpty else { throw MailCollectionError.emptyName }
        let available = Set(try accounts().map(\.id))
        guard collection.links.allSatisfy({ available.contains($0.accountID) && !$0.remoteMessageID.isEmpty }) else { throw GmailError.reconnect }
        var seen = Set<String>()
        collection.links = collection.links.filter { seen.insert($0.id).inserted }
        collection.updatedAt = Date()
        try context.transaction {
            try setMetadata(collection.key, value: String(decoding: try JSONEncoder().encode(collection), as: UTF8.self))
            try context.save()
        }
    }
    func deleteCollection(_ collection: MailCollection) throws {
        try context.transaction { try setMetadata(collection.key, value: nil); try context.save() }
    }
    func removeCollectionAccount(_ accountID: UUID) throws {
        for row in try context.fetch(FetchDescriptor<StoreMetadata>()) where row.key.hasPrefix(MailCollection.prefix) {
            var collection = try MailCollection.decode(row)
            guard collection.links.contains(where: { $0.accountID == accountID }) else { continue }
            collection.links.removeAll { $0.accountID == accountID }
            row.value = String(decoding: try JSONEncoder().encode(collection), as: UTF8.self)
        }
    }
}
