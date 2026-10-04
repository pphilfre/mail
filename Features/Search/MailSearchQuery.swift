import Foundation

struct MailSearchFilters: Equatable, Codable, Sendable {
    var unread = false
    var starred = false
    var attachments = false
    var active: Bool { unread || starred || attachments }
}

struct SavedMailSearch: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var version = 1
    let name: String
    let query: String
    let accountID: UUID?
    let includeTrashAndSpam: Bool
    let filters: MailSearchFilters

    static func decode(_ raw: String) -> [SavedMailSearch] {
        let rows = (try? JSONDecoder().decode([SavedMailSearch].self, from: Data(raw.utf8))) ?? []
        return rows.filter { $0.version == 1 }
    }
    static func encode(_ searches: [SavedMailSearch]) -> String {
        guard let data = try? JSONEncoder().encode(searches) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct MailSearchQuery: Sendable {
    enum Field: String, Sendable { case from, to, subject, label, before, after, has; case status = "is" }
    struct Clause: Sendable { let field: Field; let value: String; let date: Date? }
    var terms: [String] = []
    var clauses: [Clause] = []
    var error: String?
    var active: Bool { !terms.isEmpty || !clauses.isEmpty }

    init(_ raw: String) {
        var tokens: [(value: String, literal: Bool)] = []
        var current = ""; var quoted = false; var escaping = false; var literal = false
        for character in raw {
            if escaping { current.append(character); escaping = false; continue }
            if character == "\\" { escaping = true; continue }
            if character == "\"" { if current.isEmpty { literal = true }; quoted.toggle(); continue }
            if character.isWhitespace && !quoted {
                if !current.isEmpty { tokens.append((current, literal)); current = ""; literal = false }
            } else { current.append(character) }
        }
        if escaping { current.append("\\") }
        guard !quoted else { error = "Close the quotation mark to search for a phrase."; return }
        if !current.isEmpty { tokens.append((current, literal)) }
        for token in tokens {
            guard !token.literal, let colon = token.value.firstIndex(of: ":"), let field = Field(rawValue: String(token.value[..<colon]).lowercased()) else {
                terms.append(token.value); continue
            }
            let value = String(token.value[token.value.index(after: colon)...])
            guard !value.isEmpty else { error = "Add a value after \(field.rawValue):"; return }
            var date: Date?
            switch field {
            case .before, .after:
                date = Self.parseDate(value)
                guard date != nil else { error = "Use a real date in YYYY-MM-DD format after \(field.rawValue):"; return }
            case .has:
                guard value.lowercased() == "attachment" else { error = "Use has:attachment to find files."; return }
            case .status:
                guard ["unread", "read", "starred"].contains(value.lowercased()) else { error = "Use is:unread, is:read or is:starred."; return }
            default: break
            }
            clauses.append(Clause(field: field, value: value, date: date))
        }
    }
    private static func parseDate(_ value: String) -> Date? {
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let parts = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: parts) else { return nil }
        let checked = calendar.dateComponents([.year, .month, .day], from: date)
        return checked.year == year && checked.month == month && checked.day == day ? date : nil
    }
}
