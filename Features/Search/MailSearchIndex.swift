import Foundation

/// Value snapshots keep SwiftData models on the main actor while the index builds elsewhere.
struct MailSearchDocument: Equatable, Sendable {
    let id: UUID
    let accountID: UUID?
    let fields: [String]
    var isTrash = false
    var isSpam = false
    var sender = ""
    var recipients: [String] = []
    var subject = ""
    var labels: [String] = []
    var receivedAt = Date.distantPast
    var isRead = true
    var isStarred = false
    var hasAttachments = false
    var semanticText = ""
}

/// A disposable substring index over cached metadata. No schema migration or provider calls.
struct MailSearchIndex: Sendable {
    private struct Entry: Sendable {
        let document: MailSearchDocument
        let fields: [String]
    }
    private var entries: [Entry] = []
    private var postings: [String: Set<Int>] = [:]

    init(documents: [MailSearchDocument] = []) {
        for document in documents {
            guard !Task.isCancelled else { return }
            let fields = document.fields.map(Self.normalize)
            let position = entries.count
            entries.append(Entry(document: document, fields: fields))
            for gram in Set(fields.flatMap { Self.trigrams($0) }) {
                postings[gram, default: []].insert(position)
            }
        }
    }

    /// Terms may match different fields. Preserve source order (newest mail first).
    func matches(_ query: String, accountID: UUID? = nil, includeTrashAndSpam: Bool = false, filters: MailSearchFilters = MailSearchFilters(), ignoringTerms: Bool = false) -> [UUID] {
        let parsed = MailSearchQuery(query)
        guard parsed.error == nil, parsed.active || filters.active else { return [] }
        let terms = ignoringTerms ? [] : parsed.terms.map(Self.normalize)
        let grams = Set(terms.flatMap { Self.trigrams($0) })
        var candidates: Set<Int>?
        // Intersect the shortest postings first, then verify real substrings to reject collisions.
        for gram in grams.sorted(by: { (postings[$0]?.count ?? 0) < (postings[$1]?.count ?? 0) }) {
            guard let positions = postings[gram] else { return [] }
            if let previous = candidates { candidates = previous.intersection(positions) }
            else { candidates = positions }
            if candidates?.isEmpty == true { return [] }
        }
        let positions = candidates?.sorted() ?? Array(entries.indices)
        return positions.compactMap { position in
            let entry = entries[position]
            guard Self.eligible(entry.document, query: parsed, accountID: accountID, includeTrashAndSpam: includeTrashAndSpam, filters: filters),
                  terms.allSatisfy({ term in entry.fields.contains { $0.contains(term) } }) else { return nil }
            return entry.document.id
        }
    }

    static func eligible(_ document: MailSearchDocument, query: MailSearchQuery, accountID: UUID?,
                         includeTrashAndSpam: Bool, filters: MailSearchFilters) -> Bool {
        (accountID == nil || document.accountID == accountID)
        && (includeTrashAndSpam || (!document.isTrash && !document.isSpam))
        && (!filters.unread || !document.isRead)
        && (!filters.starred || document.isStarred)
        && (!filters.attachments || document.hasAttachments)
        && query.clauses.allSatisfy { matches($0, document: document) }
    }

    private static func matches(_ clause: MailSearchQuery.Clause, document: MailSearchDocument) -> Bool {
        let value = normalize(clause.value)
        switch clause.field {
        case .from: return normalize(document.sender).contains(value)
        case .to: return document.recipients.contains { normalize($0).contains(value) }
        case .subject: return normalize(document.subject).contains(value)
        case .label: return document.labels.contains { normalize($0) == value }
        case .before: return clause.date.map { document.receivedAt < $0 } ?? false
        case .after: return clause.date.map { document.receivedAt >= $0 } ?? false
        case .has: return document.hasAttachments
        case .status:
            switch value {
            case "read": return document.isRead
            case "unread": return !document.isRead
            default: return document.isStarred
            }
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func trigrams(_ text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= 3 else { return [] }
        return (0...(scalars.count - 3)).map { offset in
            String(String.UnicodeScalarView(scalars[offset..<(offset + 3)]))
        }
    }
}
