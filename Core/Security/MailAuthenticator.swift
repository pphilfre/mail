import Foundation

actor MailAuthenticator {
    private let resolver: any AuthenticationTXTResolver
    init(resolver: any AuthenticationTXTResolver = AuthenticationDNS()) { self.resolver = resolver }
    func analyse(raw: Data, expectedSender: String, now: Date = Date()) async -> [SecurityFinding] {
        let spf = SecurityFinding(id: "spf", title: "SPF", verdict: .unknown,
            explanation: "Independent SPF verification needs trusted SMTP envelope and receiving-IP metadata. Neither cached headers nor original message text establish those inputs. Reported SPF headers are not trusted.")
        do {
            let original = try DKIMVerifier.original(raw)
            let fromHeaders = original.headers.filter { $0.name.lowercased() == "from" }
            guard fromHeaders.count == 1 else { throw AuthenticationError.unavailable("Original message has missing or multiple From headers.") }
            let from = MailMIME.addresses(fromHeaders[0].value.replacingOccurrences(of: "\r\n", with: ""))
            guard from.count == 1, MailMIME.valid(from[0].email), from[0].email.lowercased() == expectedSender.lowercased() else { throw AuthenticationError.unavailable("Original From address is ambiguous or differs from the cached sender. Refresh the message before verification.") }
            let fromDomain = SenderSecurity.domain(from[0].email)
            let indices = original.headers.indices.filter { original.headers[$0].name.lowercased() == "dkim-signature" }
            guard indices.count <= 8 else { throw AuthenticationError.unavailable("More than eight DKIM signatures; verification coverage is incomplete.") }
            var passed: [String] = [], failed = 0, unavailable: [String] = []
            for index in indices {
                if Task.isCancelled { throw CancellationError() }
                do {
                    let signature = try DKIMVerifier.signature(original.headers[index], index: index, now: now)
                    let records = try await resolver.records(signature.selector + "._domainkey." + signature.domain)
                    let keys = records.filter { (try? DKIMVerifier.tags($0)["p"]) != nil }
                    guard keys.count == 1 else { throw AuthenticationError.unavailable("DKIM DNS key missing or ambiguous for \(signature.domain). Historical keys may have rotated.") }
                    if try DKIMVerifier.verify(original, signature: signature, keyRecord: keys[0]) { passed.append(signature.domain) }
                    else { failed += 1 }
                } catch { unavailable.append(error.localizedDescription) }
            }
            let dkim = SecurityFinding(id: "dkim", title: "DKIM", verdict: !passed.isEmpty ? .checked : (failed > 0 ? .concern : .unknown),
                explanation: (!passed.isEmpty ? "Original Gmail message signature and complete body verified locally for: \(Array(Set(passed)).sorted().joined(separator: ", "))." : failed > 0 ? "\(failed) original message signature/body checks failed against the current DNS key. Transit modification or key rotation can cause failures." : "No supported DKIM signature could be verified.") +
                    " Only selected signed headers and the body are authenticated; unsigned headers may change. DNS keys came from Google Public DNS over HTTPS; DNSSEC is not independently validated. This authenticates a signing domain, not a person or message safety. " + unavailable.joined(separator: " "), points: passed.isEmpty && failed > 0 ? 20 : 0)
            let dmarc: SecurityFinding
            if passed.contains(fromDomain) {
                do {
                    let records = try await resolver.records("_dmarc." + fromDomain)
                    dmarc = try Self.dmarc(records: records, fromDomain: fromDomain, verifiedDomains: passed)
                } catch { dmarc = SecurityFinding(id: "dmarc", title: "DMARC", verdict: .unknown, explanation: error.localizedDescription) }
            } else {
                dmarc = SecurityFinding(id: "dmarc", title: "DMARC", verdict: .unknown,
                    explanation: "No cryptographically verified DKIM domain exactly matches the original From domain. SPF is unknown. Relaxed organisational-domain alignment and parent-domain/PSD policy discovery are not implemented; a DMARC failure cannot be inferred.")
            }
            var findings = [spf, dkim, dmarc]
            if !passed.isEmpty && failed > 0 {
                findings.append(SecurityFinding(id: "dkim-failures", title: "Other DKIM signatures", verdict: .concern,
                    explanation: "\(failed) other full-body signature/body checks failed against current DNS keys. Another signing domain verified, but these failures remain evidence of modification or key rotation.", points: 20))
            }
            return findings
        } catch {
            return [spf] + ["dkim", "dmarc"].map { SecurityFinding(id: $0, title: $0.uppercased(), verdict: .unknown, explanation: error.localizedDescription) }
        }
    }
    nonisolated static func dmarc(records: [String], fromDomain: String, verifiedDomains: [String]) throws -> SecurityFinding {
        let policies = records.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("v=DMARC1;") }
        guard policies.count == 1 else { throw AuthenticationError.unavailable("Exact From-domain DMARC policy is missing or ambiguous. Parent-domain and public-suffix discovery are not implemented.") }
        let tags = try DKIMVerifier.tags(policies[0])
        guard ["none", "quarantine", "reject"].contains(tags["p"] ?? ""),
              ["r", "s"].contains(tags["adkim"] ?? "r"), verifiedDomains.contains(fromDomain) else { throw AuthenticationError.unavailable("DMARC policy is malformed or no verified DKIM domain is aligned.") }
        return SecurityFinding(id: "dmarc", title: "DMARC", verdict: .checked,
            explanation: "Original From domain \(fromDomain) exactly aligns with a cryptographically verified full-body DKIM signature. Exact-domain DNS policy: p=\(tags["p"] ?? ""), adkim=\(tags["adkim"] ?? "r"). This satisfies both strict and relaxed DKIM alignment for this message. Policy was fetched now, not at delivery; SPF remains unknown. Authentication does not certify message safety.")
    }
}
