import Foundation

/// Value snapshots keep SwiftData models on the main actor while the index builds elsewhere.
struct MailSearchDocument: Equatable, Sendable {
    let id: UUID
    let accountID: UUID?
    let fields: [String]
    var isTrash = false
    var isSpam = false
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
    func matches(_ query: String, accountID: UUID? = nil, includeTrashAndSpam: Bool = false) -> [UUID] {
        let terms = Self.normalize(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }
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
            guard accountID == nil || entry.document.accountID == accountID,
                  includeTrashAndSpam || (!entry.document.isTrash && !entry.document.isSpam),
                  terms.allSatisfy({ term in entry.fields.contains { $0.contains(term) } }) else { return nil }
            return entry.document.id
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
