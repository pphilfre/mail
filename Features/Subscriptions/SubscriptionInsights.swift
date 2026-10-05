import Foundation

struct SubscriptionEntry: Identifiable {
    var id: String { email }
    let email: String
    let name: String
    let messages: [MailMessage]
    let weeklyCount: Int
    let manuallyIncluded: Bool
    @MainActor var unreadCount: Int { messages.filter { !$0.isRead }.count }
}

@MainActor enum SubscriptionInsights {
    static func likelyNewsletter(_ message: MailMessage) -> Bool {
        let title = [message.subject, message.senderName ?? "", message.senderEmail].joined(separator: " ")
        if title.range(of: #"\b(newsletter|digest|roundup|bulletin|weekly update|daily update)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // Avoid scanning entire HTML bodies on the UI thread. Snippets and cached plain text provide a conservative signal.
        let text = message.snippet + " " + String((message.plainTextBody ?? "").prefix(8192))
        return text.range(of: #"\b(unsubscribe|manage (?:your )?(?:email )?preferences)\b"#, options: [.regularExpression, .caseInsensitive]) != nil &&
            title.range(of: #"\b(receipt|invoice|order confirmation|payment|refund|shipping|delivery)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
    }
    static func entries(_ messages: [MailMessage], rules: [SubscriptionRule], accountID: UUID?, now: Date = Date(), calendar: Calendar = .current) -> [SubscriptionEntry] {
        let rules = Dictionary(uniqueKeysWithValues: rules.map { ($0.key, $0) })
        let eligible = messages.filter { !$0.isSent && !$0.isDraft && !$0.isSpam && !$0.isTrash && MailMIME.valid($0.senderEmail) &&
            (accountID == nil || $0.accountID == accountID) }
        let grouped = Dictionary(grouping: eligible, by: { SenderInsights.normalise($0.senderEmail) })
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return grouped.compactMap { email, rows in
            let perAccount = Dictionary(grouping: rows, by: \.accountID)
            let included = perAccount.values.flatMap { scoped -> [MailMessage] in
                guard let first = scoped.first else { return [] }
                if let rule = rules[SubscriptionRule.prefix(first.accountID) + email] { return rule.included ? scoped : [] }
                return scoped.contains(where: likelyNewsletter) ? scoped : []
            }.sorted { $0.receivedAt != $1.receivedAt ? $0.receivedAt > $1.receivedAt : $0.identity < $1.identity }
            guard let latest = included.first else { return nil }
            return SubscriptionEntry(email: email, name: latest.sender.displayName, messages: included,
                weeklyCount: included.filter { $0.receivedAt >= weekStart && $0.receivedAt <= now }.count,
                manuallyIncluded: included.contains { rules[SubscriptionRule.prefix($0.accountID) + email]?.included == true })
        }.sorted { $0.unreadCount != $1.unreadCount ? $0.unreadCount > $1.unreadCount : $0.email < $1.email }
    }
}
