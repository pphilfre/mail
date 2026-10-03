import Foundation
import CoreFoundation

enum MailMIME {
    static func addresses(_ value: String) -> [MailAddress] {
        var pieces: [String] = []; var current = ""; var quoted = false; var angle = 0
        for character in value {
            if character == "\"" { quoted.toggle() }
            if !quoted && character == "<" { angle += 1 }
            if !quoted && character == ">" { angle = max(0, angle - 1) }
            if (character == "," || character == ";") && !quoted && angle == 0 {
                pieces.append(current); current = ""
            } else { current.append(character) }
        }
        pieces.append(current)
        return pieces.compactMap { piece in
            let text = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if let start = text.firstIndex(of: "<"), let end = text.lastIndex(of: ">"), start < end {
                let name = String(text[..<start]).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                return MailAddress(name: name.isEmpty ? nil : decodedHeader(name), email: String(text[text.index(after: start)..<end]))
            }
            return MailAddress(name: nil, email: text)
        }
    }
    static func valid(_ value: String) -> Bool {
        guard !value.contains(where: { $0.isWhitespace || $0.isNewline || "<>(),;:\"".contains($0) }) else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }
    static func decodedHeader(_ value: String) -> String {
        let value = value.replacingOccurrences(of: "(?<=\\?=)[\\t\\r\\n ]+(?==\\?)", with: "", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=") else { return value }
        var result = value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let whole = Range(match.range, in: value), let charset = Range(match.range(at: 1), in: value),
                  let encoding = Range(match.range(at: 2), in: value), let content = Range(match.range(at: 3), in: value) else { continue }
            let data: Data?
            if value[encoding].lowercased() == "b" { data = Data(base64Encoded: String(value[content])) }
            else {
                let bytes = Array(value[content].replacingOccurrences(of: "_", with: " ").utf8)
                var decoded: [UInt8] = []; var index = 0
                while index < bytes.count {
                    if bytes[index] == 61, index + 2 < bytes.count,
                       let byte = UInt8(String(bytes: bytes[(index + 1)...(index + 2)], encoding: .ascii) ?? "", radix: 16) {
                        decoded.append(byte); index += 3
                    } else { decoded.append(bytes[index]); index += 1 }
                }
                data = Data(decoded)
            }
            if let data, let text = decodeText(data, charset: String(value[charset])) { result.replaceSubrange(whole, with: text) }
        }
        return result
    }
    static func decodeText(_ data: Data, charset: String? = nil) -> String? {
        if let charset {
            let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cf != kCFStringEncodingInvalidId,
               let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) { return text }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
    struct Content: Sendable { var text = ""; var html = ""; var attachments: [GmailPart] = [] }
    static func inlineImages(_ root: GmailPart?, depth: Int = 0) -> [GmailPart] {
        guard let root, depth < 40 else { return [] }
        let safeTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]
        let current = root.header("Content-ID") != nil && safeTypes.contains(root.mimeType?.lowercased() ?? "") ? [root] : []
        return current + (root.parts ?? []).flatMap { inlineImages($0, depth: depth + 1) }
    }
    static func content(_ root: GmailPart?) -> Content {
        var output = Content()
        func visit(_ part: GmailPart, depth: Int) {
            guard depth < 40 else { return }
            let disposition = part.header("Content-Disposition")?.lowercased() ?? ""
            if !(part.filename ?? "").isEmpty || disposition.hasPrefix("attachment") {
                output.attachments.append(part); return
            }
            if let data = part.body?.data.flatMap(Base64URL.decode) {
                let header = part.header("Content-Type") ?? ""
                let charset = header.components(separatedBy: "charset=").dropFirst().first?.components(separatedBy: ";").first?
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                let text = decodeText(data, charset: charset) ?? ""
                if part.mimeType?.lowercased() == "text/plain" { output.text += text + "\n" }
                if part.mimeType?.lowercased() == "text/html" { output.html += text + "\n" }
            }
            for child in part.parts ?? [] { visit(child, depth: depth + 1) }
        }
        if let root { visit(root, depth: 0) }
        return output
    }
    /// Native text only: no web view, JavaScript, navigation or remote-image loading.
    static func readableHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style|head)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<(?:br|/p|/div|/tr|/li|/h[1-6])\\b[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<[^>]*>", with: "", options: .regularExpression)
        for (entity, replacement) in ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&"] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let whole = Range(match.range, in: text), let value = Range(match.range(at: 1), in: text) else { continue }
                let string = String(text[value]); let hex = string.hasPrefix("x")
                if let number = UInt32(hex ? String(string.dropFirst()) : string, radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) {
                    text.replaceSubrange(whole, with: String(scalar))
                }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func encodedWord(_ value: String) -> String {
        // Keep each RFC 2047 word under 75 characters without splitting UTF-8 scalars.
        var chunks: [Data] = []; var chunk = Data()
        for scalar in value.unicodeScalars {
            let bytes = Data(String(scalar).utf8)
            if chunk.count + bytes.count > 42 { chunks.append(chunk); chunk = Data() }
            chunk.append(bytes)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks.map { "=?UTF-8?B?\($0.base64EncodedString())?=" }.joined(separator: "\r\n ")
    }
    static func raw(_ draft: LocalDraft, from: String, requireRecipient: Bool = true) throws -> String {
        let values = [draft.to, draft.cc, draft.bcc, draft.subject, from, draft.inReplyTo ?? "", draft.referencesHeader ?? ""]
        guard !values.contains(where: { $0.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }), valid(from),
              (!requireRecipient || !addresses(draft.to).isEmpty) else { throw GmailError.invalidRecipients }
        let recipientLists = [addresses(draft.to), addresses(draft.cc), addresses(draft.bcc)]
        guard recipientLists.flatMap({ $0 }).allSatisfy({ valid($0.email) }) else { throw GmailError.invalidRecipients }
        func header(_ list: [MailAddress]) -> String {
            list.map { address in address.name.map { encodedWord($0) + " <" + address.email + ">" } ?? address.email }.joined(separator: ", ")
        }
        var lines = ["From: \(from)", "To: \(header(recipientLists[0]))"]
        if !recipientLists[1].isEmpty { lines.append("Cc: \(header(recipientLists[1]))") }
        if !recipientLists[2].isEmpty { lines.append("Bcc: \(header(recipientLists[2]))") }
        lines += ["Subject: " + encodedWord(draft.subject), "Message-ID: <\(draft.id.uuidString.lowercased())@dev.freddiephilpot.dispatch>",
                  "MIME-Version: 1.0", "Content-Type: text/plain; charset=UTF-8", "Content-Transfer-Encoding: base64"]
        if let reply = draft.inReplyTo { lines.append("In-Reply-To: " + reply) }
        if let references = draft.referencesHeader { lines.append("References: " + references) }
        let encoded = Data(draft.body.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return Base64URL.encode(Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + encoded + "\r\n").utf8))
    }
}
