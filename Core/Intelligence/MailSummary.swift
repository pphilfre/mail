import Foundation

struct MailSummarySource: Sendable, Equatable {
    let sender: String
    let subject: String
    let text: String?
    let html: String?
    var receivedAt: Date? = nil
}

enum MailSummaryPreparation {
    /// Never substitute the subject or inbox preview for a missing body.
    static func body(_ source: MailSummarySource, includeQuotedHistory: Bool = false) -> String {
        let plain = source.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let extracted: String
        if plain.isEmpty {
            var html = source.html ?? ""
            if !includeQuotedHistory {
                html = html.replacingOccurrences(of: #"(?is)<blockquote\b[^>]*>.*?</blockquote\s*>"#, with: "", options: .regularExpression)
            }
            html = html.replacingOccurrences(of: #"(?is)<(div|span)\b[^>]*(?:display\s*:\s*none|visibility\s*:\s*hidden)[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression)
            extracted = MailMIME.readableHTML(html)
        } else {
            extracted = plain
        }
        var lines: [String] = []
        var signature = false
        for line in extracted.components(separatedBy: .newlines) {
            var clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let quoteBoundary = clean.range(of: #"(?i)^(On .+wrote:|-{2,}\s*(Original Message|Forwarded message)\s*-*|Begin forwarded message:)$"#, options: .regularExpression) != nil
            if quoteBoundary {
                if !includeQuotedHistory { break }
                signature = false
            }
            if clean == "--" || clean.range(of: #"(?i)^Sent from my (iPhone|iPad|Android).*$"#, options: .regularExpression) != nil { signature = true; continue }
            if signature { continue }
            if clean.hasPrefix(">") && !includeQuotedHistory { continue }
            while clean.hasPrefix(">") { clean = String(clean.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if clean.range(of: #"(?i)^(unsubscribe|manage (email )?preferences|view (this email )?in (your )?browser)\s*[:|]?.*$"#, options: .regularExpression) != nil { continue }
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
                if let split = window.lastIndex(where: { $0 == "\n" || $0 == " " }), window.distance(from: window.startIndex, to: split) > maximum / 2 {
                    end = window.index(after: split)
                }
            }
            output.append(String(remainder[..<end]))
            remainder = remainder[end...]
        }
        return output
    }

    static func inputs(_ sources: [MailSummarySource], maximum: Int) throws -> [String] {
        guard !sources.isEmpty else { throw MailSummaryError.missingBody }
        let rawBytes = sources.reduce(0) { total, source in
            let plain = source.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return total + (plain.isEmpty ? source.html?.utf8.count ?? 0 : plain.utf8.count)
        }
        guard rawBytes <= 20_000_000 else { throw MailSummaryError.tooLarge }
        let ordered = sources.enumerated().sorted {
            let left = $0.element.receivedAt ?? .distantPast, right = $1.element.receivedAt ?? .distantPast
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        var previousBodies: [String] = []
        var inputs: [String] = []
        var readableBytes = 0
        for (index, source) in ordered.enumerated() {
            try Task.checkCancellation()
            let complete = body(source, includeQuotedHistory: true)
            guard !complete.isEmpty else { throw MailSummaryError.missingBody }
            readableBytes += complete.utf8.count
            guard readableBytes <= 2_000_000 else { throw MailSummaryError.tooLarge }
            // Preserve quoted history when its source message hasn't been downloaded.
            let authored = body(source)
            let hasEarlierCopy = previousBodies.contains { $0.count > 20 && complete.contains($0) }
            let preparedBody = hasEarlierCopy && !authored.isEmpty ? authored : complete
            previousBodies.append(authored)
            let header = "Message \(index + 1), from \(String(source.sender.prefix(120)))\nSubject: \(String(source.subject.prefix(240)))\nBody:\n"
            inputs += chunks(preparedBody, maximum: max(100, maximum - header.count)).map { header + $0 }
        }
        guard inputs.count <= 40 else { throw MailSummaryError.tooLarge }
        return inputs
    }

    static func paragraph(_ output: String) throws -> String {
        let clean = LocalModelWorker.clean(output)
            .replacingOccurrences(of: #"(?m)^\s*(?:[-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*(?:summary|here is (?:a |the )?summary)\s*:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.lowercased().contains("key passages from message bodies"),
              !clean.lowercased().contains("<email_text>") else { throw LocalModelError.empty }
        return clean
    }
}

struct MailSummaryResult: Sendable {
    let text: String
    let generated: Bool
    var missingBodies = 0
}

/// Every body chunk contributes, including late decisions; reduction keeps chronology.
@MainActor enum MailSummaryPipeline {
    static func run(_ inputs: [String], maximum: Int, generate: (String) async throws -> String) async throws -> String {
        guard !inputs.isEmpty else { throw MailSummaryError.missingBody }
        var partial: [String] = []
        for input in inputs {
            try Task.checkCancellation()
            partial.append(try MailSummaryPreparation.paragraph(await generate(input)))
        }
        for _ in 0..<8 {
            if partial.count == 1 { return partial[0] }
            let combined = partial.enumerated().map { "Part \($0.offset + 1): \($0.element)" }.joined(separator: "\n")
            let batches = MailSummaryPreparation.chunks(combined, maximum: maximum)
            var next: [String] = []
            for batch in batches {
                try Task.checkCancellation()
                next.append(try MailSummaryPreparation.paragraph(await generate(batch)))
            }
            guard next.count < partial.count || next.joined().count < partial.joined().count else { throw LocalModelError.incomplete }
            partial = next
        }
        throw MailSummaryError.tooLarge
    }
}

@MainActor extension LocalMailModel {
    func summarise(_ sources: [MailSummarySource]) async throws -> MailSummaryResult {
        guard canWrite else { throw LocalModelError.missing }
        let maximum = Self.systemAvailable ? 4_500 : 2_600
        let preparation = Task.detached(priority: .userInitiated) { try MailSummaryPreparation.inputs(sources, maximum: maximum) }
        let inputs = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
        try Task.checkCancellation()
        let text = try await MailSummaryPipeline.run(inputs, maximum: maximum) { try await self.generate(.summary, text: $0) }
        return MailSummaryResult(text: text, generated: true)
    }
}

enum MailSummaryError: LocalizedError {
    case missingBody, tooLarge
    var errorDescription: String? {
        switch self {
        case .missingBody: "A message body isn’t downloaded yet. Refresh the conversation and try again."
        case .tooLarge: "This conversation is too large to summarise reliably on this device."
        }
    }
}
