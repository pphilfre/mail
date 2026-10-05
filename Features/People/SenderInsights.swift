import Foundation

struct SenderActivity: Identifiable, Equatable, Sendable {
    var id: Date { week }
    let week: Date
    var count: Int
}

struct SenderSubjectCount: Identifiable, Equatable, Sendable {
    var id: String { subject }
    let subject: String
    let count: Int
}

struct SenderDirectoryEntry: Identifiable, Equatable, Sendable {
    var id: String { email }
    let email: String
    let name: String
    let receivedCount: Int
    let unreadCount: Int
    let lastReceivedAt: Date
}

@MainActor enum SenderInsights {
    static func normalise(_ email: String) -> String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    static func received(_ messages: [MailMessage], email: String, accountID: UUID?) -> [MailMessage] {
        let email = normalise(email)
        return messages.filter { !$0.isDraft && !$0.isSpam && !$0.isTrash && !$0.isSent &&
            normalise($0.senderEmail) == email && (accountID == nil || $0.accountID == accountID) }
            .sorted { $0.receivedAt != $1.receivedAt ? $0.receivedAt > $1.receivedAt : $0.identity < $1.identity }
    }
    static func sent(_ messages: [MailMessage], email: String, accountID: UUID?) -> [MailMessage] {
        let email = normalise(email)
        return messages.filter { $0.isSent && !$0.isDraft && !$0.isSpam && !$0.isTrash &&
            (accountID == nil || $0.accountID == accountID) && ($0.to + $0.cc + $0.bcc).contains { normalise($0.email) == email } }
            .sorted { $0.receivedAt != $1.receivedAt ? $0.receivedAt > $1.receivedAt : $0.identity < $1.identity }
    }
    static func directory(_ messages: [MailMessage], accountID: UUID?) -> [SenderDirectoryEntry] {
        let incoming = messages.filter { !$0.isDraft && !$0.isSpam && !$0.isTrash && !$0.isSent && MailMIME.valid($0.senderEmail) &&
            (accountID == nil || $0.accountID == accountID) }
        return Dictionary(grouping: incoming, by: { normalise($0.senderEmail) }).map { email, rows in
            let sorted = rows.sorted { $0.receivedAt != $1.receivedAt ? $0.receivedAt > $1.receivedAt : $0.identity < $1.identity }
            let name = sorted.compactMap(\.senderName).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? email
            return SenderDirectoryEntry(email: email, name: name, receivedCount: rows.count,
                unreadCount: rows.filter { !$0.isRead }.count, lastReceivedAt: sorted[0].receivedAt)
        }.sorted { $0.lastReceivedAt != $1.lastReceivedAt ? $0.lastReceivedAt > $1.lastReceivedAt : $0.email < $1.email }
    }
    static func activity(_ messages: [MailMessage], now: Date = Date(), calendar: Calendar = .current) -> [SenderActivity] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (-7...0).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return SenderActivity(week: start, count: messages.filter { $0.receivedAt >= start && $0.receivedAt < end && $0.receivedAt <= now }.count)
        }
    }
    static func commonSubjects(_ messages: [MailMessage]) -> [SenderSubjectCount] {
        let subjects = messages.map {
            let value = $0.subject.replacingOccurrences(of: #"^(?:(?:re|fw|fwd):\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "No subject" : value
        }
        return Dictionary(grouping: subjects, by: { $0 }).map { SenderSubjectCount(subject: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.subject < $1.subject }
    }
    static func linkedTasks(_ tasks: [MailTask], received: [MailMessage]) -> [MailTask] {
        let messages = Set(received.map(\.identity))
        let threads = Set(received.filter { !$0.remoteThreadID.isEmpty }.map { "\($0.accountID.uuidString):\($0.remoteThreadID)" })
        return tasks.filter { messages.contains("\($0.accountID.uuidString):\($0.remoteMessageID)") ||
            (!$0.remoteThreadID.isEmpty && threads.contains("\($0.accountID.uuidString):\($0.remoteThreadID)")) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
