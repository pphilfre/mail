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
    var bodyText: String {
        let plain = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rich = html.map(MailMIME.readableHTML) ?? ""
        return String((plain.isEmpty ? (rich.isEmpty ? snippet : rich) : plain + "\n" + rich).prefix(65_536))
    }
    @MainActor init(_ message: MailMessage) {
        id = message.id; accountID = message.accountID; remoteID = message.remoteID
        senderName = message.senderName; senderEmail = message.senderEmail; subject = message.subject
        snippet = message.snippet; text = message.plainTextBody
        html = message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }
        receivedAt = message.receivedAt
    }
}

enum ReceiptFlow: String, Codable, CaseIterable, Hashable, Sendable {
    case incoming, outgoing, unknown
    var title: String { self == .incoming ? "Money in" : self == .outgoing ? "Money out" : "Unconfirmed direction" }
    var sign: String { self == .incoming ? "+" : self == .outgoing ? "−" : "" }
}

struct ReceiptFact: Identifiable, Equatable, Sendable {
    let label: String
    let value: String
    var id: String { label }
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
    var flow = ReceiptFlow.outgoing
    var facts: [ReceiptFact] = []
    var signedAmount: String { money.map { flow.sign + $0.display } ?? "?" }
}

enum ReceiptDetector {
    static func detect(_ source: ReceiptSource) -> ReceiptSummary? {
        let subject = source.subject.lowercased()
        let negative = #"\b(special offer|discount code|sale ends|abandoned cart|order cancel(?:led|ed)|payment (?:failed|declined)|unsubscribe confirmation)\b"#
        guard subject.range(of: negative, options: .regularExpression) == nil else { return nil }
        let body = source.bodyText
        let positive = #"\b(receipt|invoice|order (?:confirmation|confirmed)|purchase confirmation|payment (?:received|confirmation|successful)|your order|thank(?:s| you) for your (?:order|purchase)|refund (?:confirmation|processed|issued)|you (?:paid|sent|received)|payment (?:to|from)|money (?:sent|received)|transfer (?:complete|completed|sent|received))\b"#
        let subjectMatches = subject.range(of: positive, options: .regularExpression) != nil
        let bodyMatches = body.prefix(4000).lowercased().range(of: positive, options: .regularExpression) != nil
        let money = amount(in: source.text ?? "") ?? source.html.flatMap { amount(in: MailMIME.readableHTML($0)) }
            ?? amount(in: body) ?? amount(in: source.subject)
        let transaction = #"\b(order (?:number|id|#)|transaction (?:id|number)|paid on|payment method|billing address)\b"#
        let hasTransaction = body.lowercased().range(of: transaction, options: .regularExpression) != nil
        guard subjectMatches || (money != nil && (bodyMatches || hasTransaction)) else { return nil }
        let context = subject + "\n" + String(body.prefix(4000)).lowercased()
        let purchase = matches(#"\b(order (?:number|id|#|total|confirmation)|item|product|purchase|billing address|shipping address)\b"#, context)
        let transfer = !purchase && matches(#"\b(transfer|you sent|money sent|money received|sent you|friends and family|payment from|you received)\b"#, context)
        let refund = matches(#"\b(refund (?:confirmation|processed|issued|completed)|you(?:'ve| have)? been refunded|received a refund)\b"#, context)
        let incoming = matches(#"\b(you(?:'ve| have)? received|money received|payment from|sent you|paid you|credited to your|deposited into your)\b"#, context)
        let outgoing = matches(#"\b(you(?:'ve| have)? (?:paid|sent)|money sent|payment to|amount (?:paid|charged)|total paid|paid with|payment successful)\b"#, context)
        let flow: ReceiptFlow = refund || incoming ? .incoming : outgoing || (purchase && !subject.contains("invoice")) ? .outgoing : .unknown
        let kind = refund ? "Refund" : transfer ? "Transfer" : subject.contains("invoice") ? "Invoice" : incoming ? "Payment received" : "Purchase"
        return ReceiptSummary(id: source.id, accountID: source.accountID, remoteID: source.remoteID,
            merchant: merchant(source), kind: kind, money: money, subject: source.subject,
            senderEmail: source.senderEmail, receivedAt: source.receivedAt, flow: flow, facts: facts(in: body))
    }
    static func merchant(_ source: ReceiptSource) -> String {
        if let merchant = field(#"(?:merchant|seller|paid to|payment to|payment from|purchase from)"#, in: source.bodyText),
           !merchant.contains("@"), merchant.range(of: #"[£€$¥]"#, options: .regularExpression) == nil { return merchant }
        let name = source.senderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? source.senderEmail : name
    }
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func field(_ label: String, in text: String) -> String? {
        let pattern = #"(?im)^\s*"# + label + #"\s*[:#=–-]\s*([^\r\n]{1,120})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func facts(in text: String) -> [ReceiptFact] {
        let labels: [(String, String)] = [
            ("Order number", #"order (?:number|id|no\.?)"#), ("Transaction", #"transaction (?:id|number)"#),
            ("Invoice", #"invoice (?:number|id|no\.?)"#), ("Payment method", #"(?:payment method|paid with)"#),
            ("Item", #"(?:item|product|description)"#), ("Quantity", "quantity"),
            ("Subtotal", "subtotal"), ("Tax", #"(?:tax|vat)"#), ("Delivery", #"(?:shipping|delivery)"#),
            ("Transaction date", #"(?:transaction date|payment date|paid on)"#), ("Status", #"(?:payment status|order status)"#)
        ]
        return labels.compactMap { title, label in field(label, in: text).map { ReceiptFact(label: title, value: $0) } }
    }
    static func amount(in text: String) -> ReceiptMoney? {
        let text = String(text.prefix(65_536))
        // Strong total labels outrank line items, subtotal, shipping and tax.
        for label in [#"\b(?:grand total|order total|total paid|amount paid|amount charged|payment amount)\b"#, #"\b(?:total|amount due|paid)\b"#] {
            guard let regex = try? NSRegularExpression(pattern: label + #"\s{0,30}[:=–-]?\s{0,30}([^\r\n]{1,100})"#, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text), let money = firstMoney(in: String(text[range])) { return money }
            }
        }
        // With several unlabelled amounts, leave the total unknown for review.
        let candidates = moneyMatches(in: text)
        return candidates.count == 1 ? candidates.first : nil
    }
    private static func firstMoney(in text: String) -> ReceiptMoney? { moneyMatches(in: text).first }
    static func enteredAmount(_ input: String) -> Decimal? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]+(?:[.,][0-9]{1,2})?$"#, options: .regularExpression) != nil,
              value.filter(\.isNumber).count <= 12 else { return nil }
        return Decimal(string: value.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }
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
