import Foundation

struct MailSummarySource: Sendable, Equatable {
    let sender: String
    let subject: String
    let text: String?
    let html: String?
}

enum MailSummaryPreparation {
    /// Keep every paragraph, exclude quoted history duplicated in a conversation, and never use subjects as bodies.
    static func body(_ source: MailSummarySource, includeQuotedHistory: Bool = false) -> String {
        let plain = source.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let extracted = plain.isEmpty ? MailMIME.readableHTML(source.html ?? "") : plain
        if includeQuotedHistory {
            return extracted.components(separatedBy: .newlines).map { line in
                var value = line.trimmingCharacters(in: .whitespaces)
                while value.hasPrefix(">") { value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces) }
                return value
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lines: [String] = []
        for line in extracted.components(separatedBy: .newlines) {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean == "--" || clean == "-- " { break }
            if clean.hasPrefix(">") { continue }
            if clean.range(of: #"^On .+wrote:$"#, options: .regularExpression) != nil { break }
            if !clean.isEmpty { lines.append(clean) }
        }
        return lines.joined(separator: "\n")
    }
    static func chunks(_ text: String, maximum: Int = 5_000) -> [String] {
        guard maximum > 0 else { return [] }
        var remainder = text[...]
        var output: [String] = []
        while !remainder.isEmpty {
            var end = remainder.index(remainder.startIndex, offsetBy: maximum, limitedBy: remainder.endIndex) ?? remainder.endIndex
            if end != remainder.endIndex {
                let window = remainder[..<end]
                if let split = window.lastIndex(of: "\n"), window.distance(from: window.startIndex, to: split) > maximum / 2 { end = split }
            }
            output.append(String(remainder[..<end]))
            remainder = remainder[end...]
            if remainder.first == "\n" { remainder = remainder.dropFirst() }
        }
        return output
    }
}

struct MailSummaryResult: Sendable {
    let text: String
    let generated: Bool
}

@MainActor extension LocalMailModel {
    func summarise(_ sources: [MailSummarySource]) async throws -> MailSummaryResult {
        let preparation = Task.detached(priority: .userInitiated) {
            sources.map { source in
                (source.sender, source.subject, MailSummaryPreparation.body(source, includeQuotedHistory: sources.count == 1))
            }.filter { !$0.2.isEmpty }
        }
        let prepared = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
        try Task.checkCancellation()
        guard !prepared.isEmpty else { throw MailSummaryError.missingBody }
        guard prepared.reduce(0, { $0 + $1.2.utf8.count }) <= 2_000_000 else { throw MailSummaryError.tooLarge }
        let full = prepared.map { "From: \($0.0)\nSubject: \($0.1)\n\($0.2)" }.joined(separator: "\n\n")
        // Extraction is reliable on older hardware; the 0.6B model is unsuitable for factual summaries.
        if Self.systemAvailable, full.count <= 100_000 {
            do {
                let chunks = MailSummaryPreparation.chunks(full)
                var partial: [String] = []
                for chunk in chunks {
                    try Task.checkCancellation()
                    partial.append(try await generate(.summary, text: chunk))
                }
                let combined = partial.joined(separator: "\n")
                if chunks.count == 1 { return MailSummaryResult(text: combined, generated: true) }
                if combined.count <= 6_000 {
                    return MailSummaryResult(text: try await generate(.summary, text: combined), generated: true)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { /* Context limits, language availability, or guardrails: show source evidence instead. */ }
        }
        let work = Task.detached(priority: .userInitiated) {
            var excerpts: [String] = []
            for (sender, subject, body) in prepared {
                if Task.isCancelled { break }
                for chunk in MailSummaryPreparation.chunks(body, maximum: 12_000) {
                    if Task.isCancelled { break }
                    excerpts += LocalMailAnalysis.summary(chunk, subject: subject, limit: 2).map { sender + ": " + $0 }
                }
            }
            return excerpts
        }
        let excerpts = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        try Task.checkCancellation()
        return MailSummaryResult(text: excerpts.map { "• " + $0 }.joined(separator: "\n"), generated: false)
    }
}

enum MailSummaryError: LocalizedError {
    case missingBody, tooLarge
    var errorDescription: String? {
        switch self {
        case .missingBody: "The message body isn’t downloaded yet. Refresh the conversation and try again."
        case .tooLarge: "This conversation exceeds the 2 MB summary limit. Read the full messages below."
        }
    }
}
