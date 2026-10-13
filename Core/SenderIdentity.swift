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
    static func declaredIconURLs(html: String, page: URL, suffixes: MailPublicSuffixes = .bundled) -> [URL] {
        guard let host = page.host, page.scheme == "https" else { return [] }
        let root = suffixes.registrableDomain(host) ?? host
        func attribute(_ name: String, tag: String) -> String? {
            let pattern = #"(?i)\b"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
            for index in 1...3 {
                if let range = Range(match.range(at: index), in: tag) { return String(tag[range]) }
            }
            return nil
        }
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<link\b[^>]{0,2048}>"#) else { return [] }
        var seen = Set<URL>()
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range, in: html) else { return nil }
            let tag = String(html[range])
            guard let rel = attribute("rel", tag: tag)?.lowercased(),
                  rel.split(whereSeparator: \.isWhitespace).contains(where: { ["icon", "apple-touch-icon", "apple-touch-icon-precomposed"].contains(String($0)) }),
                  let href = attribute("href", tag: tag),
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: page)?.absoluteURL,
                  url.scheme == "https", url.user == nil, url.password == nil, let iconHost = url.host,
                  (suffixes.registrableDomain(iconHost) ?? iconHost) == root,
                  !url.pathExtension.lowercased().contains("svg"), seen.insert(url).inserted else { return nil }
            return url
        }
    }
    static func iconURLs(email: String, suffixes: MailPublicSuffixes = .bundled) -> [URL] {
        let domains = iconDomains(email: email, suffixes: suffixes)
        guard let root = domains.last else { return [] }
        let hosts = Array(domains.reversed()) + (root.hasPrefix("www.") ? [] : ["www." + root])
        return hosts.flatMap { host in
            ["favicon.ico", "apple-touch-icon.png", "favicon.png"].compactMap { URL(string: "https://\(host)/\($0)") }
        }
    }
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
