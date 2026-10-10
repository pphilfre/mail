import Foundation

enum SecurityVerdict: String, Sendable {
    case checked, unknown, concern
    var symbol: String {
        switch self { case .checked: "checkmark.circle"; case .unknown: "questionmark.circle"; case .concern: "xmark.circle" }
    }
}

struct SecurityFinding: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let verdict: SecurityVerdict
    let explanation: String
    var points: Int = 0
}

/// A score measures observed concerns, never the probability that a message is safe.
struct SecurityReport: Equatable, Sendable {
    let findings: [SecurityFinding]
    var score: Int { min(100, findings.reduce(0) { $0 + max(0, $1.points) }) }
    var unknownCount: Int { findings.filter { $0.verdict == .unknown }.count }
    var verdict: SecurityVerdict {
        findings.contains { $0.verdict == .concern } ? .concern :
            (unknownCount > 0 || findings.isEmpty ? .unknown : .checked)
    }
}

enum MailSecurityContent {
    static func fingerprint(_ message: MailMessage, attachments: [MailAttachment]) -> String {
        var data = Data((message.senderEmail + (message.senderName ?? "") + message.replyTo.map(\.email).joined(separator: ",")).utf8)
        data.append(message.cachedHTML ?? Data()); data.append(message.cachedText ?? Data())
        data.append(Data(attachments.map { "\($0.id):\($0.cachedRelativePath ?? ""):\($0.mimeType):\($0.filename)" }.joined(separator: "\n").utf8))
        return MailSecurityObservations.sha256(data)
    }
}

enum MailAuthentication {
    /// Gmail REST exposes message headers, not a separate authenticated verdict. Even an
    /// mx.google.com authserv-id can be forged in imported mail. Never promote it to trusted.
    static func findings(headers: [GmailHeader]) -> [SecurityFinding] {
        let results = headers.filter { $0.name.lowercased() == "authentication-results" }.map(\.value)
        return ["spf", "dkim", "dmarc"].map { method in
            let pattern = "(?i)(?:^|;)\\s*" + method + "(?:/[0-9]+)?\\s*=\\s*([a-z]+)\\b"
            let values = results.flatMap { MailSecurityObservations.matches(pattern, in: $0, group: 1) }
            let summary = values.isEmpty ? "No result available." : "Header reports: " + values.joined(separator: ", ") + "."
            return SecurityFinding(id: method, title: method.uppercased(), verdict: .unknown,
                explanation: summary + " Header provenance is unverified; this is not a verified authentication result. SPF needs the receiving IP and envelope sender; DKIM needs the original signed bytes and DNS key; DMARC needs verified aligned SPF/DKIM. Cached bodies cannot reconstruct those inputs.")
        }
    }
}

struct LocalSenderRecord: Sendable {
    let email: String
    let name: String?
    let date: Date
    let spam: Bool
}

enum SenderSecurity {
    static func domain(_ email: String) -> String {
        String(email.split(separator: "@").last ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
    static func skeleton(_ value: String) -> String {
        let substitutions: [Character: Character] = ["а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y", "і": "i", "ј": "j", "ο": "o", "ρ": "p", "α": "a", "0": "o", "1": "l"]
        return String(value.lowercased().map { substitutions[$0] ?? $0 })
    }
    static func near(_ first: String, _ second: String) -> Bool {
        guard first != second, first.count >= 5, second.count >= 5,
              abs(first.count - second.count) <= 1, first.count <= 253, second.count <= 253 else { return false }
        let a = Array(first), b = Array(second)
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count] <= 1
    }
    static func domainConcerns(_ domain: String, known: Set<String>) -> [String] {
        var concerns: [String] = []
        if domain.contains("xn--") || !domain.unicodeScalars.allSatisfy(\.isASCII) {
            concerns.append("Internationalised domain may conceal lookalike characters: \(domain). This alone does not prove phishing.")
        }
        if let match = known.sorted().first(where: { $0 != domain && (skeleton($0) == skeleton(domain) || near(domain, $0)) }) {
            concerns.append("Domain \(domain) resembles \(match), seen in earlier local mail.")
        }
        return concerns
    }
    static func findings(sender: MailAddress, replyTo: [MailAddress], history: [LocalSenderRecord]) -> [SecurityFinding] {
        let email = sender.email.lowercased(), host = domain(email)
        let known = Set(history.filter { !$0.spam }.map { domain($0.email) }.filter { !$0.isEmpty })
        var concerns = domainConcerns(host, known: known)
        let name = sender.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !name.isEmpty, let match = history.first(where: { !$0.spam && $0.name?.lowercased() == name && $0.email.lowercased() != email && domain($0.email) != host }) {
            concerns.append("Display name also belongs to \(match.email) in earlier mail; addresses differ.")
        }
        if MailMIME.valid(name), name != email { concerns.append("Display name contains a different email address: \(name).") }
        if replyTo.contains(where: { domain($0.email) != host }) { concerns.append("Reply-To uses a different domain. Mailing services can legitimately do this.") }
        if sender.email.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }) {
            concerns.append("Sender address contains control or bidirectional formatting characters.")
        }
        let previous = history.filter { $0.email.lowercased() == email }
        let spam = previous.filter(\.spam).count
        return [
            SecurityFinding(id: "identity", title: "Sender impersonation", verdict: concerns.isEmpty ? .unknown : .concern,
                explanation: concerns.isEmpty ? "No match in the local lookalike checks. Identity remains unverified; these heuristics cannot cover all homographs or brands." : concerns.joined(separator: " "), points: concerns.isEmpty ? 0 : 25),
            SecurityFinding(id: "history", title: "Local sender history", verdict: spam > 0 ? .concern : .unknown,
                explanation: "\(previous.count) earlier cached messages from this exact address; \(spam) marked as spam. History stays on this device, is account scoped, and does not authenticate a sender. A familiar address can be spoofed.", points: spam > 0 ? 15 : 0)
        ]
    }
}
