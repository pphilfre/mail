import Foundation
import NaturalLanguage

/// Provider-independent value snapshots; SwiftData objects never leave the main actor.
struct IntelligenceMail: Sendable, Equatable, Identifiable {
    let id: UUID
    let accountID: UUID
    let threadID: String
    let subject: String
    let sender: String
    let text: String
    let receivedAt: Date
    let unread: Bool
    let starred: Bool
    let labels: [String]

    @MainActor init(_ message: MailMessage) {
        id = message.id; accountID = message.accountID; threadID = message.remoteThreadID
        subject = message.subject; sender = message.sender.displayName
        // Only cached plain text; do not fetch bodies or parse HTML on the UI actor.
        text = String((message.plainTextBody ?? message.snippet).prefix(12_000))
        receivedAt = message.receivedAt; unread = !message.isRead; starred = message.isStarred
        labels = message.folderIDs
    }

    init(id: UUID = UUID(), accountID: UUID, threadID: String = "", subject: String,
         sender: String = "", text: String, receivedAt: Date = Date(), unread: Bool = true,
         starred: Bool = false, labels: [String] = []) {
        self.id = id; self.accountID = accountID; self.threadID = threadID; self.subject = subject
        self.sender = sender; self.text = String(text.prefix(12_000)); self.receivedAt = receivedAt
        self.unread = unread; self.starred = starred; self.labels = labels
    }
}

enum LocalMailCategory: String, CaseIterable, Sendable {
    case personal = "Personal", work = "Work", finance = "Finance", travel = "Travel"
    case newsletters = "Newsletters", promotions = "Promotions", other = "Other"
}

struct ExtractedMailDate: Identifiable, Sendable, Equatable {
    let phrase: String
    let date: Date
    let context: String
    let isDeadline: Bool
    var id: String { "\(phrase)-\(date.timeIntervalSince1970)" }
}

enum LocalMailAnalysis {
    static let deadlineWords = ["deadline", "due", "by", "before", "no later", "submit", "expires"]
    private static let rules: [(LocalMailCategory, Set<String>)] = [
        (.finance, ["invoice", "receipt", "payment", "refund", "statement", "billing"]),
        (.travel, ["flight", "booking", "boarding", "itinerary", "hotel", "reservation"]),
        (.promotions, ["discount", "sale", "coupon", "offer", "promotion"]),
        (.newsletters, ["newsletter", "unsubscribe", "digest", "subscribe"]),
        (.work, ["project", "meeting", "deadline", "proposal", "review", "agenda"]),
        (.personal, ["dinner", "birthday", "weekend", "family", "hello"])
    ]

    static func words(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text.lowercased()
        var result: [String] = []
        tokenizer.enumerateTokens(in: tokenizer.string!.startIndex..<tokenizer.string!.endIndex) { range, _ in
            result.append(String(tokenizer.string![range])); return true
        }
        return result
    }

    static func category(_ mail: IntelligenceMail) -> LocalMailCategory {
        if mail.labels.contains("CATEGORY_PROMOTIONS") { return .promotions }
        if mail.labels.contains("CATEGORY_SOCIAL") { return .personal }
        let body = Set(words(String(mail.text.prefix(2_000))))
        let subject = Set(words(mail.subject))
        let ranked = rules.map { category, hints in (category, hints.intersection(body).count + 2 * hints.intersection(subject).count) }
        return ranked.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? .other
    }

    static func sentences(_ text: String) -> [String] {
        let bounded = String(text.prefix(12_000))
        let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = bounded
        var result: [String] = []
        tokenizer.enumerateTokens(in: bounded.startIndex..<bounded.endIndex) { range, _ in
            let sentence = String(bounded[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty && !sentence.hasPrefix(">") { result.append(sentence) }
            return result.count < 100
        }
        return result
    }

    /// Extractive summary: selected original sentences in source order, never invented facts.
    static func summary(_ text: String, subject: String = "", limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }
        let lines = sentences(text)
        let hints = Set(words(subject))
        let ranked = lines.enumerated().map { offset, line in
            let tokens = Set(words(line))
            let action = !tokens.intersection(["please", "due", "deadline", "confirm", "review", "reply"]).isEmpty
            return (offset, hints.intersection(tokens).count * 2 + (action ? 3 : 0) + (offset == 0 ? 1 : 0))
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        return ranked.prefix(limit).map(\.0).sorted().map { String(lines[$0].prefix(600)) }
    }

    /// NSDataDetector's relative dates are wall-clock dependent. Keep only explicit year-bearing dates;
    /// relative/ambiguous phrases remain in the source summary for the person to interpret.
    static func dates(_ text: String, referenceDate: Date? = nil, calendar: Calendar = .current) -> [ExtractedMailDate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let bounded = String(text.prefix(12_000)); let ns = bounded as NSString
        let lines = sentences(bounded)
        var found: [ExtractedMailDate] = []
        for match in detector.matches(in: bounded, range: NSRange(location: 0, length: ns.length)) {
            guard let date = match.date else { continue }
            let phrase = ns.substring(with: match.range)
            guard phrase.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil else { continue }
            let context = lines.first { $0.contains(phrase) } ?? phrase
            let tokens = Set(words(context))
            let deadline = deadlineWords.contains { tokens.contains($0) || context.lowercased().contains($0 + " ") }
            let value = ExtractedMailDate(phrase: phrase, date: date, context: String(context.prefix(600)), isDeadline: deadline)
            if !found.contains(where: { $0.id == value.id }) { found.append(value) }
            if found.count == 12 { break }
        }
        if let referenceDate {
            // Relative dates belong to the email's received date, never the current wall clock.
            let relative = try? NSRegularExpression(pattern: #"\b(today|tomorrow)\b"#, options: .caseInsensitive)
            for match in relative?.matches(in: bounded, range: NSRange(location: 0, length: ns.length)) ?? [] {
                let phrase = ns.substring(with: match.range)
                let offset = phrase.lowercased() == "tomorrow" ? 1 : 0
                guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: referenceDate)) else { continue }
                let context = lines.first { $0.localizedCaseInsensitiveContains(phrase) } ?? phrase
                let deadline = !Set(words(context)).intersection(Set(deadlineWords)).isEmpty
                let label = phrase + " (" + date.formatted(date: .abbreviated, time: .omitted) + ")"
                found.append(ExtractedMailDate(phrase: label, date: date, context: String(context.prefix(600)), isDeadline: deadline))
                if found.count >= 12 { break }
            }
        }
        return found
    }

    static func importance(_ mail: IntelligenceMail) -> Int {
        let tokens = Set(words(mail.subject + " " + String(mail.text.prefix(1_000))))
        let action = !tokens.intersection(["deadline", "urgent", "due", "please", "confirm", "review"]).isEmpty
        let category = category(mail)
        return (mail.starred ? 6 : 0) + (mail.labels.contains("IMPORTANT") ? 4 : 0) + (action ? 3 : 0)
            + (category == .work || category == .personal ? 1 : 0)
            - (category == .promotions || category == .newsletters ? 2 : 0)
    }

    static func catchUp(_ mails: [IntelligenceMail], accountID: UUID?) -> [IntelligenceMail] {
        let ranked = mails.filter { $0.unread && (accountID == nil || $0.accountID == accountID) && importance($0) > 0 }
            .sorted { importance($0) == importance($1) ? $0.receivedAt > $1.receivedAt : importance($0) > importance($1) }
        var threads = Set<String>()
        return ranked.filter {
            threads.insert("\($0.accountID):\($0.threadID.isEmpty ? $0.id.uuidString : $0.threadID)").inserted
        }.prefix(20).map { $0 }
    }
}

/// Disposable bounded LRU; embeddings remain on device and are only computed during a search.
actor MailSemanticSearch {
    private struct Cached { let text: String; let vector: [Double]; let language: NLLanguage }
    private var cache: [UUID: Cached] = [:]
    private var order: [UUID] = []
    static let maximumDocuments = 1_000

    func search(_ query: String, documents: [MailSearchDocument], accountID: UUID?,
                includeTrashAndSpam: Bool, filters: MailSearchFilters) throws -> [UUID]? {
        let parsed = MailSearchQuery(query)
        guard parsed.error == nil else { return [] }
        let phrase = parsed.terms.joined(separator: " ")
        guard !phrase.isEmpty else { return nil }
        let language = NLLanguageRecognizer.dominantLanguage(for: phrase) ?? .english
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language),
              let queryVector = embedding.vector(for: phrase) else { return nil }
        // Structured filters use the existing lexical engine so their semantics cannot drift.
        let eligible = documents.lazy.filter {
            MailSearchIndex.eligible($0, query: parsed, accountID: accountID, includeTrashAndSpam: includeTrashAndSpam, filters: filters)
        }
        var ranked: [(UUID, Double)] = []
        let liveIDs = Set(documents.map(\.id)); cache = cache.filter { liveIDs.contains($0.key) }
        order.removeAll { !liveIDs.contains($0) }
        for document in eligible.prefix(Self.maximumDocuments) {
            try Task.checkCancellation()
            let text = String((document.subject + ". " + document.semanticText).prefix(1_000))
            let vector: [Double]
            if let value = cache[document.id], value.text == text, value.language == language { vector = value.vector }
            else {
                guard let value = embedding.vector(for: text) else { continue }
                vector = value; cache[document.id] = Cached(text: text, vector: value, language: language)
            }
            order.removeAll { $0 == document.id }; order.append(document.id)
            if order.count > Self.maximumDocuments { cache.removeValue(forKey: order.removeFirst()) }
            let dot = zip(queryVector, vector).reduce(0) { $0 + $1.0 * $1.1 }
            let norm = sqrt(queryVector.reduce(0) { $0 + $1 * $1 } * vector.reduce(0) { $0 + $1 * $1 })
            if norm > 0 { ranked.append((document.id, dot / norm)) }
        }
        return ranked.filter { $0.1 >= 0.35 }.sorted { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }.prefix(50).map(\.0)
    }
}
