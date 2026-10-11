import Foundation

struct MailTextItem: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var subject = ""
    var body: String
}

enum MailTextLibrary {
    static func key(_ kind: String, accountID: UUID? = nil) -> String {
        "mail-text-library:\(kind):\(accountID?.uuidString ?? "shared")"
    }
    static func read(_ kind: String, accountID: UUID? = nil, defaults: UserDefaults = .standard) -> [MailTextItem] {
        let key = key(kind, accountID: accountID)
        if let raw = defaults.string(forKey: key), let data = raw.data(using: .utf8),
           let items = try? JSONDecoder().decode([MailTextItem].self, from: data) { return items }
        if kind == "Signatures", let accountID, let legacy = defaults.string(forKey: MailSignature.key(accountID)), !legacy.isEmpty {
            return [MailTextItem(id: accountID, name: "Default", body: legacy)]
        }
        return []
    }
    static func encode(_ items: [MailTextItem]) -> String {
        String(decoding: (try? JSONEncoder().encode(items)) ?? Data("[]".utf8), as: UTF8.self)
    }
}
