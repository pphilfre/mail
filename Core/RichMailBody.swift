import Foundation

/// Portable formatting stored in draft metadata, leaving the existing SwiftData schema intact.
struct RichMailBody: Codable, Equatable, Sendable {
    struct Run: Codable, Equatable, Sendable {
        var location: Int
        var length: Int
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var link: String?
    }
    var text: String
    var runs: [Run]

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    static func safeLink(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["https", "http", "mailto", "tel"].contains(scheme)
            && !value.unicodeScalars.contains { $0.value < 32 }
    }
    func html(matching plain: String) -> String? {
        guard text == plain else { return nil } // Never send an out-of-date formatted body.
        let source = text as NSString
        var offset = 0
        var paragraphs: [String] = []
        var list: String?
        for line in text.components(separatedBy: "\n") {
            let length = (line as NSString).length
            var prefix = 0
            var kind: String?
            if line.hasPrefix("• ") { prefix = 2; kind = "ul" }
            else if let range = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                prefix = (String(line[range]) as NSString).length; kind = "ol"
            }
            if kind != list {
                if let list { paragraphs.append("</\(list)>") }
                if let kind { paragraphs.append("<\(kind)>") }
                list = kind
            }
            let start = offset + prefix, end = offset + length
            var boundaries = Set([start, end])
            let validRuns = runs.filter { $0.location >= 0 && $0.length > 0 && $0.location <= source.length && $0.length <= source.length - $0.location }
            for run in validRuns {
                if run.location < end && run.location + run.length > start {
                    boundaries.insert(max(start, run.location)); boundaries.insert(min(end, run.location + run.length))
                }
            }
            let sorted = boundaries.sorted()
            var content = ""
            for (a, b) in zip(sorted, sorted.dropFirst()) where b > a {
                var value = Self.escape(source.substring(with: NSRange(location: a, length: b - a)))
                if let run = validRuns.last(where: { $0.location <= a && $0.location + $0.length >= b }) {
                    if run.bold { value = "<strong>\(value)</strong>" }
                    if run.italic { value = "<em>\(value)</em>" }
                    if run.underline { value = "<u>\(value)</u>" }
                    if run.strike { value = "<s>\(value)</s>" }
                    if let link = run.link, Self.safeLink(link) { value = "<a href=\"\(Self.escape(link))\">\(value)</a>" }
                }
                content += value
            }
            paragraphs.append(kind == nil ? "<div>\(content.isEmpty ? "<br>" : content)</div>" : "<li>\(content)</li>")
            offset += length + 1
        }
        if let list { paragraphs.append("</\(list)>") }
        return "<!doctype html><html><body>" + paragraphs.joined() + "</body></html>"
    }
}
