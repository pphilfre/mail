import Foundation

struct ReceiptMoney: Codable, Equatable, Hashable, Sendable {
    let amount: Decimal
    let currency: String
    var display: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return currency + " " + (formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")
    }
}

struct ReceiptSource: Identifiable, Hashable, Sendable {
    let id: UUID
    let accountID: UUID
    let remoteID: String
    let senderName: String?
    let senderEmail: String
    let subject: String
    let snippet: String
    let text: String?
    let html: String?
    let receivedAt: Date
    var bodyText: String { String((text ?? html.map(MailMIME.readableHTML) ?? snippet).prefix(65_536)) }
    @MainActor init(_ message: MailMessage) {
        id = message.id; accountID = message.accountID; remoteID = message.remoteID
        senderName = message.senderName; senderEmail = message.senderEmail; subject = message.subject
        snippet = message.snippet; text = message.plainTextBody
        html = text == nil ? message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) } : nil
        receivedAt = message.receivedAt
    }
}

struct ReceiptSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let remoteID: String
    var merchant: String
    var kind: String
    var money: ReceiptMoney?
    let subject: String
    let senderEmail: String
    let receivedAt: Date
    var reviewed = false
}

enum ReceiptDetector {
    static func detect(_ source: ReceiptSource) -> ReceiptSummary? {
        let subject = source.subject.lowercased()
        let negative = #"\b(special offer|discount code|sale ends|abandoned cart|order cancel(?:led|ed)|payment (?:failed|declined)|unsubscribe confirmation)\b"#
        guard subject.range(of: negative, options: .regularExpression) == nil else { return nil }
        let body = source.bodyText
        let positive = #"\b(receipt|invoice|order confirmation|purchase confirmation|payment (?:received|confirmation)|your order|thank you for your (?:order|purchase)|refund (?:confirmation|processed))\b"#
        let subjectMatches = subject.range(of: positive, options: .regularExpression) != nil
        let bodyMatches = body.prefix(4000).lowercased().range(of: positive, options: .regularExpression) != nil
        let money = amount(in: body) ?? amount(in: source.subject)
        guard subjectMatches || (bodyMatches && money != nil) else { return nil }
        let kind = subject.contains("refund") ? "Refund" : subject.contains("invoice") ? "Invoice" : "Receipt"
        return ReceiptSummary(id: source.id, accountID: source.accountID, remoteID: source.remoteID,
            merchant: merchant(source), kind: kind, money: money, subject: source.subject,
            senderEmail: source.senderEmail, receivedAt: source.receivedAt)
    }
    static func merchant(_ source: ReceiptSource) -> String {
        let name = source.senderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? source.senderEmail : name
    }
    static func amount(in text: String) -> ReceiptMoney? {
        let text = String(text.prefix(65_536))
        // Strong total labels outrank line items, subtotal, shipping and tax.
        for label in [#"\b(?:grand total|order total|total paid|amount paid|amount charged|payment amount)\b"#, #"\b(?:total|amount due|paid)\b"#] {
            guard let regex = try? NSRegularExpression(pattern: label + #"[ \t]*[:=–-]?[ \t]*([^\r\n]{1,100})"#, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text), let money = firstMoney(in: String(text[range])) { return money }
            }
        }
        // With several unlabelled amounts, leave the total unknown for review.
        let candidates = moneyMatches(in: text)
        return candidates.count == 1 ? candidates.first : nil
    }
    private static func firstMoney(in text: String) -> ReceiptMoney? { moneyMatches(in: text).first }
    private static func moneyMatches(in text: String) -> [ReceiptMoney] {
        let codes = "GBP|EUR|USD|CAD|AUD|NZD|CHF|JPY|INR"
        let currency = "(?:" + codes + "|[£€$¥])"
        let number = #"([0-9]+(?:[.,][0-9]+|[ \u00A0][0-9]{3})*)"#
        let pattern = "(" + currency + #")\s*"# + number + "|" + number + #"\s*("# + currency + ")"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let leading = match.range(at: 1).location != NSNotFound
            guard let moneyRange = Range(match.range(at: leading ? 2 : 3), in: text),
                  let currencyRange = Range(match.range(at: leading ? 1 : 4), in: text),
                  let amount = decimal(String(text[moneyRange])) else { return nil }
            let rawCurrency = String(text[currencyRange]).uppercased()
            let code = ["£": "GBP", "€": "EUR"][rawCurrency] ?? rawCurrency
            return ReceiptMoney(amount: amount, currency: code)
        }
    }
    static func decimal(_ input: String) -> Decimal? {
        let value = input.filter { !$0.isWhitespace }
        guard !value.isEmpty, value.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }), value.filter(\.isNumber).count <= 12 else { return nil }
        let separators = value.indices.filter { value[$0] == "." || value[$0] == "," }
        var normalized = value
        if let last = separators.last {
            let tail = value[value.index(after: last)...]
            if tail.count == 2 {
                let prefix = String(value[..<last])
                let groups = prefix.split(whereSeparator: { $0 == "." || $0 == "," })
                if groups.count > 1 {
                    guard groups.dropFirst().allSatisfy({ $0.count == 3 }), (groups.first?.count ?? 0) <= 3,
                          Set(prefix.filter { $0 == "." || $0 == "," }).count <= 1 else { return nil }
                }
                normalized = prefix.filter(\.isNumber) + "." + String(tail)
            } else if tail.count == 3 {
                // Only accept well-formed thousands groups when there is no decimal part.
                let groups = value.split(whereSeparator: { $0 == "." || $0 == "," })
                guard groups.dropFirst().allSatisfy({ $0.count == 3 }), (groups.first?.count ?? 0) <= 3 else { return nil }
                normalized = value.filter(\.isNumber)
            } else { return nil }
        }
        guard let number = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), number >= 0 else { return nil }
        return number
    }
}
