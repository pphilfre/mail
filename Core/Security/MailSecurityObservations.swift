import Foundation
import CryptoKit

/// Observations of cached content only. These are never authentication or reputation verdicts.
struct MailSecurityObservations: Sendable {
    struct Link: Identifiable, Sendable {
        var id: String { destination }
        let destination: String
        let host: String
        let concerns: [String]
    }
    let links: [Link]
    let hasRemoteImages: Bool
    let possibleTrackingPixels: Int
    // Authentication headers and a trusted provider verdict are not currently persisted.
    static let statusSymbol = "questionmark.circle"

    init(html: String, text: String) {
        hasRemoteImages = MailMIME.hasRemoteImages(html)
        let images = Self.matches(#"(?is)<img\b[^>]*>"#, in: html)
        possibleTrackingPixels = images.filter {
            $0.range(of: #"(?i)(?:width|height)\s*=\s*["']?1(?:["'\s>]|px)|(?:width|height)\s*:\s*1px"#, options: .regularExpression) != nil
        }.count
        var destinations = Self.matches(#"(?is)\bhref\s*=\s*["']([^"']+)["']"#, in: html, group: 1)
            .map { $0.replacingOccurrences(of: "&amp;", with: "&") }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            destinations += detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { $0.url?.absoluteString }
        }
        var seen = Set<String>()
        links = destinations.compactMap { value in
            let destination = value.hasPrefix("//") ? "https:" + value : value
            guard seen.insert(destination).inserted, let url = URL(string: destination),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host else { return nil }
            var concerns: [String] = []
            if scheme == "http" { concerns.append("Unencrypted HTTP") }
            if url.user != nil || url.password != nil { concerns.append("Embedded credentials can obscure the destination") }
            if host.lowercased().contains("xn--") { concerns.append("Internationalised domain: check the spelling") }
            if ["bit.ly", "t.co", "tinyurl.com", "shorturl.at"].contains(host.lowercased()) { concerns.append("Shortened URL: final destination unknown") }
            return Link(destination: destination, host: host, concerns: concerns)
        }
    }
    static func matches(_ pattern: String, in value: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
            Range($0.range(at: group), in: value).map { String(value[$0]) }
        }
    }
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
