import Foundation

/// Composer value and legacy import format. OutgoingMessage persists it in SwiftData.
struct LocalDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = ""
    var updatedAt = Date()
    var accountID: UUID?
    var remoteThreadID: String?
    var inReplyTo: String?
    var referencesHeader: String?

    var isEmpty: Bool {
        [to, cc, bcc, subject, body].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var displaySubject: String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No subject" : subject
    }
}

enum DraftStoreError: LocalizedError {
    case unreadableStore

    var errorDescription: String? {
        "The saved draft file could not be read. Saving is paused to protect existing drafts."
    }
}

struct DraftStore: Sendable, DraftPersistence {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "Mail", directoryHint: .isDirectory)
            .appending(path: "foundation-drafts.json")
    }

    func load() throws -> [LocalDraft] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([LocalDraft].self, from: Data(contentsOf: fileURL))
    }

    func save(_ drafts: [LocalDraft]) throws {
        let data = try JSONEncoder().encode(drafts)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
