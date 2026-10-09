import XCTest
import CryptoKit
@testable import DispatchMail

/// Public, independently signed test vectors from RFC 8463 Appendix A (IETF Trust).
/// No private key or live DNS query is used by these tests.
@MainActor final class AuthenticationVerificationTests: XCTestCase {
    private let edKey = "v=DKIM1; k=ed25519; p=11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
    private let rsaKey = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDkHlOQoBTzWRiGs5V6NpP3idY6Wk08a5qhdR6wy5bdOKb2jLQiY/J16JYi0Qvx/byYzCNb3W91y3FutACDfzwQ/BC/e/8uBsCR+yz1Lxj+PL6lHvqMKrM3rG4hstT5QjvHO9PzoxZyVYLzBfO2EeC3Ip3G+2kryOTIKT+l/K4w3QIDAQAB"
    private var raw: Data {
        let text = """
        DKIM-Signature: v=1; a=ed25519-sha256; c=relaxed/relaxed;
         d=football.example.com; i=@football.example.com;
         q=dns/txt; s=brisbane; t=1528637909; h=from : to :
         subject : date : message-id : from : subject : date;
         bh=2jUSOH9NhtVGCQWNr9BrIAPreKQjO6Sn7XIkfJVOzv8=;
         b=/gCrinpcQOoIfuHNQIbq4pgh9kyIK3AQUdt9OdqQehSwhEIug4D11Bus
         Fa3bT3FY5OsU7ZbnKELq+eXdp1Q1Dw==
        DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed;
         d=football.example.com; i=@football.example.com;
         q=dns/txt; s=test; t=1528637909; h=from : to : subject :
         date : message-id : from : subject : date;
         bh=2jUSOH9NhtVGCQWNr9BrIAPreKQjO6Sn7XIkfJVOzv8=;
         b=F45dVWDfMbQDGHJFlXUNB2HKfbCeLRyhDXgFpEL8GwpsRe0IeIixNTe3
         DhCVlUrSjV4BwcVcOF6+FF3Zo9Rpo1tFOeS9mPYQTnGdaSGsgeefOsk2Jz
         dA+L10TeYt9BgDfQNZtKdN1WO//KgIqXP7OdEFE4LjFYNcUxZQ4FADY+8=
        From: Joe SixPack <joe@football.example.com>
        To: Suzie Q <suzie@shopping.example.net>
        Subject: Is dinner ready?
        Date: Fri, 11 Jul 2003 21:00:37 -0700 (PDT)
        Message-ID: <20030712040037.46341.5F8J@football.example.com>

        Hi.

        We lost the game.  Are you hungry yet?

        Joe.
        """
        return Data((text.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n\r\n").utf8)
    }
    func testRFC8463RSAAndEd25519VectorsAndTampering() throws {
        let original = try DKIMVerifier.original(raw)
        for (index, key) in [(0, edKey), (1, rsaKey)] {
            let signature = try DKIMVerifier.signature(original.headers[index], index: index, now: Date())
            XCTAssertTrue(try DKIMVerifier.verify(original, signature: signature, keyRecord: key))
            let changedBody = DKIMVerifier.Original(headers: original.headers, body: Data("Changed body\r\n".utf8))
            XCTAssertFalse(try DKIMVerifier.verify(changedBody, signature: signature, keyRecord: key))
            var changedHeaders = original.headers
            let fromIndex = try XCTUnwrap(changedHeaders.firstIndex { $0.name == "From" })
            changedHeaders[fromIndex] = DKIMVerifier.Header(name: "From", value: " attacker@football.example.com")
            XCTAssertFalse(try DKIMVerifier.verify(DKIMVerifier.Original(headers: changedHeaders, body: original.body), signature: signature, keyRecord: key))
        }
    }
    func testRFC6376EmptyAndWhitespaceCanonicalisation() throws {
        XCTAssertEqual(Data(SHA256.hash(data: try DKIMVerifier.canonicalBody(Data(), mode: "simple"))).base64EncodedString(), "frcCV1k9oG9oKj3dpUqdJg1PxRT2RSN/XKdLCPjaYaY=")
        XCTAssertEqual(Data(SHA256.hash(data: try DKIMVerifier.canonicalBody(Data(), mode: "relaxed"))).base64EncodedString(), "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=")
        XCTAssertEqual(try DKIMVerifier.canonicalBody(Data(" C \r\nD \t E\r\n\r\n\r\n".utf8), mode: "relaxed"), Data(" C\r\nD E\r\n".utf8))
        XCTAssertEqual(DKIMVerifier.canonicalHeader(DKIMVerifier.Header(name: "B", value: " Y\t\r\n\t Z  "), mode: "relaxed"), "b:Y Z\r\n")
    }
    func testUnsupportedAndPartialSignaturesDoNotPass() throws {
        let original = try DKIMVerifier.original(raw)
        XCTAssertThrowsError(try DKIMVerifier.signature(DKIMVerifier.Header(name: "DKIM-Signature", value: original.headers[0].value + "; l=10"), index: 0, now: Date()))
        XCTAssertThrowsError(try DKIMVerifier.tags("v=1; v=1; d=example.com"))
        XCTAssertThrowsError(try DKIMVerifier.rsaKeyData(Data([0x30, 0x82, 0xff])))
        XCTAssertThrowsError(try DKIMVerifier.verify(original, signature: DKIMVerifier.signature(original.headers[0], index: 0, now: Date()), keyRecord: edKey + "; t=y"))
    }
    func testTXTChunksAndMalformedRecords() throws {
        XCTAssertEqual(try AuthenticationDNS.txt("\"v=DKIM1; \" \"p=YWJj\""), "v=DKIM1; p=YWJj")
        XCTAssertEqual(try AuthenticationDNS.txt("\"a\\032b\""), "a b")
        XCTAssertThrowsError(try AuthenticationDNS.txt("not quoted"))
        XCTAssertThrowsError(try AuthenticationDNS.txt("\"a\\999\""))
    }
    func testDMARCRequiresVerifiedExactAlignmentAndOneValidPolicy() throws {
        XCTAssertEqual(try MailAuthenticator.dmarc(records: ["v=DMARC1; p=reject; adkim=s"], fromDomain: "example.com", verifiedDomains: ["example.com"]).verdict, .checked)
        XCTAssertThrowsError(try MailAuthenticator.dmarc(records: ["v=DMARC1; p=reject"], fromDomain: "sub.example.com", verifiedDomains: ["example.com"]))
        XCTAssertThrowsError(try MailAuthenticator.dmarc(records: [], fromDomain: "example.com", verifiedDomains: ["example.com"]))
        XCTAssertThrowsError(try MailAuthenticator.dmarc(records: ["v=DMARC1; p=reject", "v=DMARC1; p=none"], fromDomain: "example.com", verifiedDomains: ["example.com"]))
    }
    func testOriginalVerifierDoesNotTrustForgedAuthenticationResults() async {
        let raw = Data("Authentication-Results: mx.google.com; spf=pass; dkim=pass; dmarc=pass\r\nFrom: person@example.com\r\n\r\nHello\r\n".utf8)
        let results = await MailAuthenticator(resolver: FixtureResolver(records: [:])).analyse(raw: raw, expectedSender: "person@example.com")
        XCTAssertEqual(results.map(\.verdict), [.unknown, .unknown, .unknown])
    }
    func testVerifiedOriginalDKIMEnablesOnlyAlignedDMARC() async {
        let resolver = FixtureResolver(records: ["brisbane._domainkey.football.example.com": [edKey], "test._domainkey.football.example.com": [rsaKey], "_dmarc.football.example.com": ["v=DMARC1; p=reject; adkim=s"]])
        let results = await MailAuthenticator(resolver: resolver).analyse(raw: raw, expectedSender: "joe@football.example.com")
        XCTAssertEqual(results.map(\.verdict), [.unknown, .checked, .checked])
        let mismatch = await MailAuthenticator(resolver: resolver).analyse(raw: raw, expectedSender: "other@football.example.com")
        XCTAssertEqual(mismatch.map(\.verdict), [.unknown, .unknown, .unknown])
    }
}

private struct FixtureResolver: AuthenticationTXTResolver {
    let records: [String: [String]]
    func records(_ name: String) async throws -> [String] { records[name] ?? [] }
}
