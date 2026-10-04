import Foundation

enum RecipientInput {
    static func tokens(_ raw: String) -> [String] {
        var result: [String] = []; var current = ""; var quoted = false; var angle = 0
        for character in raw {
            if character == "\"" { quoted.toggle() }
            if !quoted && character == "<" { angle += 1 }
            if !quoted && character == ">" { angle -= 1 }
            if !quoted && angle == 0 && (character == "," || character == ";") {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current.trimmingCharacters(in: .whitespaces)) }
                current = ""
            } else { current.append(character) }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current.trimmingCharacters(in: .whitespaces)) }
        return result
    }

    static func address(_ token: String) -> MailAddress? {
        guard !token.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              token.filter({ $0 == "\"" }).count.isMultiple(of: 2) else { return nil }
        if token.contains("<") || token.contains(">") {
            guard token.filter({ $0 == "<" }).count == 1, token.filter({ $0 == ">" }).count == 1,
                  token.hasSuffix(">"), let start = token.firstIndex(of: "<"), let end = token.firstIndex(of: ">"),
                  start < end else { return nil }
        }
        let addresses = MailMIME.addresses(token)
        guard addresses.count == 1, let address = addresses.first, MailMIME.valid(address.email) else { return nil }
        return address
    }
    static func invalid(_ raw: String) -> [String] { tokens(raw).filter { address($0) == nil } }
    static func duplicateEmails(_ fields: [String]) -> Set<String> {
        var seen = Set<String>(); var duplicates = Set<String>()
        for address in fields.flatMap(tokens).compactMap({ Self.address($0) }) {
            let key = address.email.lowercased()
            if !seen.insert(key).inserted { duplicates.insert(key) }
        }
        return duplicates
    }
    static func formatted(_ address: MailAddress) -> String {
        guard let name = address.name, !name.isEmpty else { return address.email }
        // Names from cached mail cannot inject recipient delimiters.
        let safe = String(String.UnicodeScalarView(name.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 &&
            !CharacterSet(charactersIn: "\"<>\\").contains($0) }))
        return "\"\(safe)\" <\(address.email)>"
    }
    static func replacingLastToken(_ raw: String, with address: MailAddress) -> String {
        var pieces = tokens(raw)
        if !raw.trimmingCharacters(in: .whitespaces).hasSuffix(",") && !raw.trimmingCharacters(in: .whitespaces).hasSuffix(";") && !pieces.isEmpty {
            pieces.removeLast()
        }
        pieces.append(formatted(address))
        return pieces.joined(separator: ", ") + ", "
    }
}

struct RecipientSuggestion: Identifiable, Sendable {
    var id: String { address.email.lowercased() }
    let address: MailAddress
    let frequency: Int
    let latest: Date
}

enum MailSignature {
    static func key(_ accountID: UUID) -> String { "signature-\(accountID.uuidString)" }
    static func insert(_ signature: String, in body: String) -> String {
        guard !signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return body }
        let block = "\n\n-- \n" + signature
        if let quote = quoteBoundary(in: body) { return String(body[..<quote]) + block + String(body[quote...]) }
        return body + block
    }
    static func replace(_ previous: String, with next: String, in body: String) -> String? {
        let block = "\n\n-- \n" + previous
        if let quote = quoteBoundary(in: body) {
            let ownText = String(body[..<quote])
            guard ownText.hasSuffix(block) else { return nil }
            return insert(next, in: String(ownText.dropLast(block.count))) + String(body[quote...])
        }
        if body.hasSuffix(block) {
            return insert(next, in: String(body.dropLast(block.count)))
        }
        return nil // Preserve signatures the user has edited.
    }
    private static func quoteBoundary(in body: String) -> String.Index? {
        ["\n\nOn ", "\n\nForwarded message"].compactMap { body.range(of: $0)?.lowerBound }.min()
    }
    static func mentionsAttachment(_ body: String) -> Bool {
        let ownText = body.components(separatedBy: "\n\nOn ").first?.components(separatedBy: "\n\nForwarded message").first ?? body
        let withoutSignature = ownText.components(separatedBy: "\n\n-- \n").first ?? ownText
        return withoutSignature.range(of: #"\b(attach(?:ed|ment|ments)?|enclosed|see the file)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
