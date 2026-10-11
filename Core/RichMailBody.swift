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

    /// Preserve untouched formatting when a signature, snippet or writing revision changes plain text.
    func replacingText(with next: String) -> RichMailBody {
        let oldCharacters = Array(text), newCharacters = Array(next)
        var prefixCount = 0, suffixCount = 0
        while prefixCount < min(oldCharacters.count, newCharacters.count) && oldCharacters[prefixCount] == newCharacters[prefixCount] { prefixCount += 1 }
        while suffixCount < min(oldCharacters.count, newCharacters.count) - prefixCount && oldCharacters[oldCharacters.count - suffixCount - 1] == newCharacters[newCharacters.count - suffixCount - 1] { suffixCount += 1 }
        let prefix = String(oldCharacters.prefix(prefixCount)).utf16.count
        let oldSuffix = String(oldCharacters.suffix(suffixCount)).utf16.count
        let nextSuffix = String(newCharacters.suffix(suffixCount)).utf16.count
        let oldEnd = text.utf16.count - oldSuffix, nextEnd = next.utf16.count - nextSuffix
        var preserved: [Run] = []
        let validRuns = runs.filter { $0.location >= 0 && $0.length > 0 && $0.location <= text.utf16.count && $0.length <= text.utf16.count - $0.location }
        for run in validRuns {
            let end = run.location + run.length
            if run.location < prefix {
                var left = run; left.length = min(end, prefix) - run.location
                if left.length > 0 { preserved.append(left) }
            }
            if end > oldEnd {
                var right = run; right.location = max(run.location, oldEnd) + nextEnd - oldEnd
                right.length = end - max(run.location, oldEnd)
                if right.length > 0 { preserved.append(right) }
            }
        }
        if nextEnd > prefix, var inherited = validRuns.last(where: { $0.location <= prefix && $0.location + $0.length > prefix }) {
            inherited.location = prefix; inherited.length = nextEnd - prefix; inherited.link = nil
            preserved.append(inherited)
        }
        return RichMailBody(text: next, runs: preserved.sorted { $0.location < $1.location })
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    static func safeLink(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        guard !value.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        switch scheme {
        case "https", "http": return url.host?.isEmpty == false
        case "mailto", "tel": return !url.path.isEmpty
        default: return false
        }
    }
    func html(matching plain: String) -> String? {
        guard text == plain else { return nil } // Never send an out-of-date formatted body.
        let source = text as NSString
        var offset = 0
        var paragraphs: [String] = []
        var list: String?
        let ordered = runs.enumerated().filter { _, run in
            run.location >= 0 && run.length > 0 && run.location <= source.length && run.length <= source.length - run.location
        }.sorted { $0.element.location < $1.element.location }
        var nextRun = 0
        var active: [(offset: Int, element: Run)] = []
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
            active.removeAll { $0.element.location + $0.element.length <= start }
            while nextRun < ordered.count && ordered[nextRun].element.location < end {
                if ordered[nextRun].element.location + ordered[nextRun].element.length > start { active.append(ordered[nextRun]) }
                nextRun += 1
            }
            let validRuns = active.sorted { $0.offset < $1.offset }.map(\.element)
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
