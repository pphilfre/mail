import Foundation
import CryptoKit
import Security

/// Bounded RFC 6376 verifier. Unsupported or ambiguous inputs always remain unknown.
enum DKIMVerifier {
    struct Header: Sendable { let name: String; let value: String }
    struct Original: Sendable { let headers: [Header]; let body: Data }
    struct Signature: Sendable {
        let index: Int
        let domain: String
        let selector: String
        let tags: [String: String]
        let headerMode: String
        let bodyMode: String
    }
    static func validDNSName(_ name: String, allowUnderscore: Bool = false) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 253, name.unicodeScalars.allSatisfy(\.isASCII) else { return false }
        let allowed = allowUnderscore ? "abcdefghijklmnopqrstuvwxyz0123456789-_" : "abcdefghijklmnopqrstuvwxyz0123456789-"
        return name.lowercased().split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") && $0.allSatisfy { allowed.contains($0) }
        }
    }
    static func original(_ raw: Data) throws -> Original {
        guard raw.count <= DraftAttachmentStore.maximumBytes, let boundary = raw.range(of: Data("\r\n\r\n".utf8)),
              boundary.lowerBound <= 256_000, let block = String(data: raw[..<boundary.lowerBound], encoding: .isoLatin1) else { throw AuthenticationError.unavailable("Original message is too large or its RFC headers are unavailable.") }
        var headers: [Header] = []
        for line in block.components(separatedBy: "\r\n") {
            guard !line.contains("\n"), !line.contains("\r") else { throw AuthenticationError.unavailable("Malformed original header line endings.") }
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard let last = headers.popLast() else { throw AuthenticationError.unavailable("Malformed folded header.") }
                headers.append(Header(name: last.name, value: last.value + "\r\n" + line))
            } else {
                guard let colon = line.firstIndex(of: ":") else { throw AuthenticationError.unavailable("Malformed original header.") }
                let name = String(line[..<colon])
                guard name.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else { throw AuthenticationError.unavailable("Unsupported header field name.") }
                headers.append(Header(name: name, value: String(line[line.index(after: colon)...])))
            }
        }
        guard headers.count <= 1000 else { throw AuthenticationError.unavailable("Too many original headers.") }
        return Original(headers: headers, body: Data(raw[boundary.upperBound...]))
    }
    static func tags(_ value: String) throws -> [String: String] {
        var output: [String: String] = [:]
        for part in value.replacingOccurrences(of: "\r\n", with: "").split(separator: ";") {
            guard let equals = part.firstIndex(of: "=") else { throw AuthenticationError.unavailable("Malformed authentication tag.") }
            let key = part[..<equals].trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil, output[key] == nil else { throw AuthenticationError.unavailable("Duplicate or invalid authentication tag.") }
            output[key] = part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        return output
    }
    static func signature(_ header: Header, index: Int, now: Date) throws -> Signature {
        let values = try tags(header.value)
        guard values["v"] == "1", ["rsa-sha256", "ed25519-sha256"].contains(values["a"]?.lowercased() ?? ""), values["l"] == nil,
              let domain = values["d"]?.lowercased(), let selector = values["s"], validDNSName(domain), validDNSName(selector),
              values["b"] != nil, values["bh"] != nil, let signed = values["h"], signed.lowercased().split(separator: ":").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "from" }),
              values["q"] == nil || values["q"]?.lowercased() == "dns/txt" else { throw AuthenticationError.unavailable("Unsupported DKIM signature: requires RSA/Ed25519-SHA256, signed From, DNS/TXT and full-body coverage. Partial-body and other algorithms remain unknown.") }
        if let expiry = values["x"] {
            guard let expiry = Double(expiry), expiry.isFinite, expiry > now.timeIntervalSince1970 else { throw AuthenticationError.unavailable("DKIM signature is expired or its expiry is invalid.") }
        }
        if let timestamp = values["t"] {
            guard let timestamp = Double(timestamp), timestamp.isFinite, timestamp >= 0, timestamp <= now.timeIntervalSince1970 + 300 else { throw AuthenticationError.unavailable("DKIM signing timestamp is invalid or in the future.") }
            if let expiry = values["x"].flatMap(Double.init), expiry <= timestamp { throw AuthenticationError.unavailable("DKIM expiry precedes its signing time.") }
        }
        let modes = (values["c"] ?? "simple/simple").lowercased().split(separator: "/").map(String.init)
        guard (1...2).contains(modes.count), modes.allSatisfy({ ["simple", "relaxed"].contains($0) }) else { throw AuthenticationError.unavailable("Unsupported DKIM canonicalisation.") }
        return Signature(index: index, domain: domain, selector: selector, tags: values, headerMode: modes[0], bodyMode: modes.count == 2 ? modes[1] : "simple")
    }
    static func canonicalHeader(_ header: Header, mode: String) -> String {
        if mode == "simple" { return header.name + ":" + header.value + "\r\n" }
        let value = header.value.replacingOccurrences(of: "\r\n", with: "").replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        return header.name.lowercased() + ":" + value + "\r\n"
    }
    static func canonicalBody(_ body: Data, mode: String) throws -> Data {
        guard let body = String(data: body, encoding: .isoLatin1) else { throw AuthenticationError.unavailable("Unsupported body encoding.") }
        var lines = body.components(separatedBy: "\r\n")
        if mode == "relaxed" {
            lines = lines.map { line in
                var value = line.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
                while value.hasSuffix(" ") { value.removeLast() }
                return value
            }
        }
        while lines.last == "" { lines.removeLast() }
        let value = lines.isEmpty ? (mode == "simple" ? "\r\n" : "") : lines.joined(separator: "\r\n") + "\r\n"
        guard let data = value.data(using: .isoLatin1) else { throw AuthenticationError.unavailable("Unsupported body bytes.") }
        return data
    }
    static func signedHeaders(_ original: Original, signature: Signature) throws -> Data {
        let names = (signature.tags["h"] ?? "").lowercased().split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard names.count <= 100 else { throw AuthenticationError.unavailable("Too many signed headers.") }
        var used: Set<Int> = [signature.index], canonical = ""
        for name in names {
            if let index = original.headers.indices.reversed().first(where: { !used.contains($0) && original.headers[$0].name.lowercased() == name }) {
                used.insert(index); canonical += canonicalHeader(original.headers[index], mode: signature.headerMode)
            }
        }
        let header = original.headers[signature.index]
        // b= is removed along with surrounding folding whitespace, not the other tags.
        let pattern = #"(?is)(^|;)([ \t\r\n]*b[ \t]*=)[^;]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern), regex.numberOfMatches(in: header.value, range: NSRange(header.value.startIndex..., in: header.value)) == 1 else { throw AuthenticationError.unavailable("Ambiguous DKIM signature value.") }
        let stripped = regex.stringByReplacingMatches(in: header.value, range: NSRange(header.value.startIndex..., in: header.value), withTemplate: "$1$2")
        let final = canonicalHeader(Header(name: header.name, value: stripped), mode: signature.headerMode)
        canonical += String(final.dropLast(2))
        guard let data = canonical.data(using: .isoLatin1) else { throw AuthenticationError.unavailable("Unsupported signed header bytes.") }
        return data
    }
    static func base64(_ value: String?) -> Data? {
        guard let value else { return nil }
        return Data(base64Encoded: value.filter { !" \t\r\n".contains($0) })
    }
    static func verify(_ original: Original, signature: Signature, keyRecord: String) throws -> Bool {
        let keyTags = try tags(keyRecord)
        let algorithm = signature.tags["a"]?.lowercased() ?? ""
        let requiredKeyType = algorithm == "ed25519-sha256" ? "ed25519" : "rsa"
        guard keyTags["v"] == nil || keyTags["v"] == "DKIM1", (keyTags["k"] ?? "rsa").lowercased() == requiredKeyType,
              keyTags["h"] == nil || keyTags["h"]?.lowercased().split(separator: ":").contains("sha256") == true,
              keyTags["s"] == nil || keyTags["s"]?.split(separator: ":").contains(where: { $0 == "*" || $0.lowercased() == "email" }) == true,
              let bytes = base64(keyTags["p"]), !bytes.isEmpty else { throw AuthenticationError.unavailable("DKIM key is missing, revoked, malformed or uses unsupported parameters.") }
        let flags = (keyTags["t"] ?? "").lowercased().split(separator: ":")
        guard !flags.contains("y") else { throw AuthenticationError.unavailable("DKIM key is in testing mode; authentication remains unknown.") }
        if let identity = signature.tags["i"] {
            let domain = SenderSecurity.domain(identity)
            guard domain == signature.domain || (domain.hasSuffix("." + signature.domain) && !flags.contains("s")) else { throw AuthenticationError.unavailable("DKIM signing identity does not match its domain/key restrictions.") }
        }
        guard let signatureBytes = base64(signature.tags["b"]), let expectedHash = base64(signature.tags["bh"]), expectedHash.count == 32 else { throw AuthenticationError.unavailable("Malformed DKIM signature encoding.") }
        let body = try canonicalBody(original.body, mode: signature.bodyMode)
        guard Data(SHA256.hash(data: body)) == expectedHash else { return false }
        let headers = try signedHeaders(original, signature: signature)
        if algorithm == "ed25519-sha256" {
            guard bytes.count == 32 else { throw AuthenticationError.unavailable("Malformed DKIM Ed25519 public key.") }
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: bytes)
            return key.isValidSignature(signatureBytes, for: Data(SHA256.hash(data: headers)))
        }
        let keyData = try rsaKeyData(bytes)
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil),
              let keyAttributes = SecKeyCopyAttributes(key) as? [String: Any],
              let size = keyAttributes[kSecAttrKeySizeInBits as String] as? Int, size >= 1024, size <= 8192,
              SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256) else { throw AuthenticationError.unavailable("Unsupported DKIM RSA key.") }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, headers as CFData, signatureBytes as CFData, nil)
    }
    static func rsaKeyData(_ data: Data) throws -> Data {
        // Security accepts PKCS#1. DNS commonly publishes SubjectPublicKeyInfo, which
        // is unwrapped only after verifying the RSA algorithm identifier and bit string.
        let bytes = Array(data)
        func element(_ start: Int) throws -> (tag: UInt8, content: Range<Int>, end: Int) {
            guard start + 2 <= bytes.count else { throw AuthenticationError.unavailable("Malformed RSA DER key.") }
            var cursor = start + 2, length = Int(bytes[start + 1])
            if length >= 128 {
                let count = length & 127
                guard (1...4).contains(count), cursor + count <= bytes.count else { throw AuthenticationError.unavailable("Malformed RSA DER length.") }
                length = 0
                for index in cursor..<cursor + count { length = length * 256 + Int(bytes[index]) }
                cursor += count
            }
            guard length <= bytes.count - cursor else { throw AuthenticationError.unavailable("Truncated RSA DER key.") }
            return (bytes[start], cursor..<cursor + length, cursor + length)
        }
        let top = try element(0)
        guard top.tag == 0x30, top.end == bytes.count else { throw AuthenticationError.unavailable("Malformed RSA DER key.") }
        let first = try element(top.content.lowerBound)
        if first.tag == 0x02 { return data }
        let rsaAlgorithm = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
        guard first.tag == 0x30, Data(bytes[top.content.lowerBound..<first.end]) == rsaAlgorithm else { throw AuthenticationError.unavailable("Unsupported DKIM public key algorithm.") }
        let bitString = try element(first.end)
        guard bitString.tag == 0x03, bitString.end == top.end, !bitString.content.isEmpty, bytes[bitString.content.lowerBound] == 0 else { throw AuthenticationError.unavailable("Malformed RSA public key bit string.") }
        return Data(bytes[(bitString.content.lowerBound + 1)..<bitString.content.upperBound])
    }
}
