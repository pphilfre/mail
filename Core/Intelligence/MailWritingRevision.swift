import Foundation

enum MailWritingRevision {
    enum Change: Equatable { case unchanged, added, removed }
    struct Run: Equatable {
        let text: String
        let change: Change
    }
    static func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
    static func instruction(_ task: LocalWritingTask, source: String, retry: Bool = false) -> String {
        let count = wordCount(source)
        let target: String
        switch task {
        case .shorten: target = "Rewrite in \(max(1, count * 40 / 100))–\(max(1, count * 60 / 100)) words. Remove repetition, filler and unnecessary background; combine sentences. Keep essential facts, names, amounts, deadlines and requests. A few synonym substitutions are not shortening."
        case .expand: target = "Aim for \(max(count + 1, count * 140 / 100))–\(max(count + 2, count * 175 / 100)) words. Explain existing points clearly and structure the request. Add no new facts, dates or commitments."
        default: target = ""
        }
        return task.instruction + " " + target + (retry ? " The previous attempt did not change the length enough. Follow the word target carefully." : "")
    }
    static func meetsLengthTarget(_ task: LocalWritingTask, source: String, revision: String) -> Bool {
        let before = wordCount(source), after = wordCount(revision)
        guard after > 0 else { return false }
        // Very short passages may have no expendable words; do not encourage removing essential facts.
        guard before >= 20 else { return true }
        switch task {
        case .shorten: return after <= before * 70 / 100
        case .expand: return after >= before * 125 / 100
        default: return true
        }
    }
    static func runs(original: String, revised: String) -> [Run] {
        // Whitespace remains attached to its word so paragraphs survive the comparison.
        func tokens(_ value: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: #"\s*\S+"#) else { return [] }
            let ns = value as NSString
            return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        }
        let old = tokens(original), next = tokens(revised)
        let oldWords = old.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let newWords = next.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var removed = Set<Int>(), added = Set<Int>()
        for change in newWords.difference(from: oldWords) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var runs: [Run] = [], i = 0, j = 0
        while i < old.count || j < next.count {
            if i < old.count && removed.contains(i) { runs.append(.init(text: old[i], change: .removed)); i += 1 }
            else if j < next.count && added.contains(j) { runs.append(.init(text: next[j], change: .added)); j += 1 }
            else if j < next.count {
                runs.append(.init(text: next[j], change: .unchanged)); j += 1; i += 1
            } else { i += 1 }
        }
        // Adjacent replacements of the first word otherwise have no separating whitespace.
        for index in runs.indices.dropFirst() where runs[index].change != runs[index - 1].change {
            if runs[index].text.first?.isWhitespace == false {
                runs[index] = Run(text: " " + runs[index].text, change: runs[index].change)
            }
        }
        return runs
    }
}
