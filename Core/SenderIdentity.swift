import Foundation

/// Uses the bundled Mozilla Public Suffix List, including private tenant suffixes.
struct MailPublicSuffixes: Sendable {
    private let rules: Set<String>
    init(text: String) {
        rules = Set(text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }.map { rule in
                let prefix = rule.hasPrefix("!") ? "!" : rule.hasPrefix("*.") ? "*." : ""
                let host = String(rule.dropFirst(prefix.count))
                return prefix + (URL(string: "https://" + host)?.host ?? host).lowercased()
            })
    }
    static let bundled: MailPublicSuffixes = {
        let text = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return MailPublicSuffixes(text: text)
    }()
    func registrableDomain(_ domain: String) -> String? {
        // Fail closed if the resource was omitted from the app bundle.
        guard !rules.isEmpty else { return nil }
        let labels = domain.lowercased().split(separator: ".").map(String.init)
        var suffixLength = 1
        for index in labels.indices {
            let suffix = labels[index...].joined(separator: ".")
            if rules.contains("!" + suffix) { suffixLength = labels.count - index - 1; break }
            if rules.contains(suffix) { suffixLength = max(suffixLength, labels.count - index) }
            if index > 0 && rules.contains("*." + suffix) { suffixLength = max(suffixLength, labels.count - index + 1) }
        }
        guard labels.count > suffixLength else { return nil }
        return labels.suffix(suffixLength + 1).joined(separator: ".")
    }
}

enum SenderIdentity {
    static func iconDomains(email: String, suffixes: MailPublicSuffixes = .bundled) -> [String] {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return [] }
        let domain = parts[1].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard domain.count <= 253, labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-" && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }),
              labels.last?.contains(where: \.isLetter) == true,
              !["localhost", "local", "internal", "invalid", "test"].contains(String(labels.last ?? "")) else { return [] }
        let root = suffixes.registrableDomain(domain)
        let personal = ["gmail.com", "outlook.com", "hotmail.com", "icloud.com", "yahoo.com", "live.com", "aol.com"]
        guard !personal.contains(root ?? domain) else { return [] }
        return [domain] + (root != nil && root != domain ? [root!] : [])
    }
    static func category(email: String, context: String) -> LocalMailCategory {
        let value = (email + " " + context).lowercased()
        let rules: [(LocalMailCategory, [String])] = [
            (.finance, ["invoice", "receipt", "payment", "billing", "statement"]),
            (.travel, ["flight", "boarding", "hotel", "itinerary", "reservation"]),
            (.promotions, ["sale", "discount", "coupon", "offer"]),
            (.newsletters, ["newsletter", "digest", "unsubscribe", "no-reply", "noreply"]),
            (.work, ["meeting", "project", "proposal", "review"])
        ]
        for (category, words) in rules where words.contains(where: value.contains) { return category }
        return .personal
    }
}
