import XCTest
import CoreImage
import UIKit
import SwiftData
@testable import DispatchMail

@MainActor final class MailSecurityTests: XCTestCase {
    func testForgedAuthenticationHeadersNeverBecomeVerified() {
        let results = MailAuthentication.findings(headers: [GmailHeader(name: "Authentication-Results", value: "mx.google.com; spf=pass; dkim=pass; dmarc=pass"),
            GmailHeader(name: "Authentication-Results", value: "attacker.invalid; spf=fail; dkim=fail")])
        XCTAssertEqual(results.map(\.verdict), [.unknown, .unknown, .unknown])
        XCTAssertTrue(results[0].explanation.contains("pass, fail"))
        XCTAssertEqual(MailAuthentication.findings(headers: []).map(\.verdict), [.unknown, .unknown, .unknown])
        XCTAssertEqual(SecurityReport(findings: results).verdict, .unknown)
    }
    func testScoreDoesNotCallUnknownSafeAndCapsEvidence() {
        let unknown = SecurityFinding(id: "missing", title: "Missing", verdict: .unknown, explanation: "Not scanned")
        XCTAssertEqual(SecurityReport(findings: [unknown]).score, 0)
        XCTAssertEqual(SecurityReport(findings: [unknown]).verdict, .unknown)
        XCTAssertEqual(SecurityReport(findings: []).verdict, .unknown)
        let concern = SecurityFinding(id: "bad", title: "Bad", verdict: .concern, explanation: "Evidence", points: 60)
        XCTAssertEqual(SecurityReport(findings: [concern, concern, unknown]).score, 100)
        XCTAssertEqual(SecurityReport(findings: [concern, unknown]).verdict, .concern)
    }
    func testLookalikesNamesAndReplyToAreEvidenceNotVerification() {
        let history = [LocalSenderRecord(email: "accounts@paypal.com", name: "Accounts", date: .distantPast, spam: false)]
        let findings = SenderSecurity.findings(sender: MailAddress(name: "Accounts", email: "accounts@paypa1.com"), replyTo: [MailAddress(email: "attacker@elsewhere.com")], history: history)
        XCTAssertEqual(findings[0].verdict, .concern)
        XCTAssertTrue(findings[0].explanation.contains("paypal.com"))
        XCTAssertTrue(findings[0].explanation.contains("Reply-To"))
        XCTAssertEqual(SenderSecurity.findings(sender: MailAddress(email: "accounts@paypal.com"), replyTo: [], history: history)[1].verdict, .unknown)
        XCTAssertFalse(SenderSecurity.domainConcerns("pаypal.com", known: ["paypal.com"]).isEmpty)
        XCTAssertFalse(SenderSecurity.domainConcerns("xn--example.com", known: []).isEmpty)
    }
    func testSenderHistoryIsEarlierAndAccountScopedAndHeadersDeletedWithAccount() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        container.mainContext.insert(account)
        func insert(accountID: UUID, date: Date) -> MailMessage {
            let row = MailMessage(accountID: accountID, remoteID: UUID().uuidString, remoteThreadID: "t", sender: MailAddress(email: "sender@example.com"), subject: "s", snippet: "", receivedAt: date)
            container.mainContext.insert(row); return row
        }
        let now = Date()
        let current = insert(accountID: account.id, date: now)
        _ = insert(accountID: account.id, date: now.addingTimeInterval(-60))
        _ = insert(accountID: UUID(), date: now.addingTimeInterval(-60))
        _ = insert(accountID: account.id, date: now.addingTimeInterval(60))
        try repository.saveSecurityHeaders([GmailHeader(name: "Authentication-Results", value: "mx.google.com; spf=pass")], messageID: current.id)
        try container.mainContext.save()
        XCTAssertEqual(try repository.senderSecurityHistory(for: current).count, 1)
        XCTAssertEqual(try repository.securityHeaders(current.id).count, 1)
        let id = current.id
        try repository.removeAccountData(id: account.id)
        XCTAssertTrue(try repository.securityHeaders(id).isEmpty)
    }
    func testAttachmentMismatchExecutableUnknownAndValidTypes() throws {
        let pdf = Data("%PDF-1.7\n".utf8)
        XCTAssertTrue(try AttachmentSecurity.inspect(pdf, filename: "report.pdf", declaredMIME: "application/pdf").previewAllowed)
        let mismatch = try AttachmentSecurity.inspect(pdf, filename: "photo.jpg", declaredMIME: "image/jpeg")
        XCTAssertEqual(mismatch.type.verdict, .concern); XCTAssertFalse(mismatch.previewAllowed)
        let executable = try AttachmentSecurity.inspect(Data([0x4d, 0x5a, 0, 0]), filename: "report.pdf", declaredMIME: "application/pdf")
        XCTAssertEqual(executable.type.verdict, .concern); XCTAssertFalse(executable.previewAllowed)
        let unknown = try AttachmentSecurity.inspect(Data([0, 1, 2]), filename: "report.pdf", declaredMIME: "application/pdf")
        XCTAssertEqual(unknown.type.verdict, .unknown); XCTAssertFalse(unknown.previewAllowed)
        XCTAssertFalse(try AttachmentSecurity.inspect(Data("<script>evil()</script>".utf8), filename: "body.html", declaredMIME: "text/html").previewAllowed)
        let text = try AttachmentSecurity.inspect(Data("hello".utf8), filename: "notes.txt", declaredMIME: "text/plain")
        XCTAssertTrue(text.previewAllowed)
        XCTAssertEqual(try AttachmentSecurity.inspect(Data([0x50, 0x4b, 0x03, 0x04]), filename: "report.docx", declaredMIME: "image/jpeg").type.verdict, .concern)
        XCTAssertEqual(text.hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
    func testVisionDecodesQRWithoutOpeningDestination() throws {
        let payload = "http://example.com/private?token=abc"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let image = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let background = CIImage(color: CIColor.white).cropped(to: image.extent.insetBy(dx: -32, dy: -32))
        let padded = image.composited(over: background)
        let cgImage = try XCTUnwrap(CIContext(options: [.useSoftwareRenderer: true]).createCGImage(padded, from: padded.extent))
        let data = try XCTUnwrap(UIImage(cgImage: cgImage).pngData())
        let results = try QRCodeSecurity.payloads(data)
        XCTAssertTrue(results.contains(payload))
        XCTAssertEqual(QRCodeSecurity.finding(results).verdict, .concern)
        let html = "<img src=\"data:image/png;base64,\(data.base64EncodedString())\"><img src=\"https://example.com/remote.png\">"
        XCTAssertEqual(QRCodeSecurity.embeddedImages(html), [data])
        XCTAssertThrowsError(try QRCodeSecurity.payloads(Data("not an image".utf8)))
    }
    func testPixelsRemovedAndRemoteContentCSPBlocked() {
        let html = "<img src='https://tracker.invalid/open' width='1' height='1'><img src='https://example.com/image' width='100'>"
        let blocked = MailHTMLView.document(html, remoteImages: false)
        XCTAssertFalse(blocked.contains("tracker.invalid"))
        XCTAssertTrue(blocked.contains("img-src data:"))
        XCTAssertTrue(blocked.contains("connect-src 'none'"))
        XCTAssertFalse(MailHTMLView.document(html, remoteImages: true).contains("tracker.invalid"))
        XCTAssertTrue(MailHTMLView.document(html, remoteImages: true).contains("example.com/image"))
    }
    func testVirusTotalUsesLookupIdentifiersAndMissingStaleReportsStayUnknown() throws {
        let target = ReputationTarget.url("https://example.com/a?private=token")
        XCTAssertEqual(String(data: try XCTUnwrap(Base64URL.decode(String(target.path.dropFirst(5)))), encoding: .utf8), target.sharedValue)
        XCTAssertTrue(ReputationTarget.fileHash(String(repeating: "a", count: 64)).path.hasPrefix("files/"))
        let request = try VirusTotalReputation.request(target, apiKey: "test-key")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.host, "www.virustotal.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-apikey"), "test-key")
        XCTAssertThrowsError(try VirusTotalReputation.request(.url("file:///private/mail"), apiKey: "test-key"))
        XCTAssertThrowsError(try VirusTotalReputation.request(.fileHash("../../private"), apiKey: "test-key"))
        XCTAssertThrowsError(try VirusTotalReputation.request(target, apiKey: ""))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func report(date: Double, malicious: Int) -> Data {
            Data("{\"data\":{\"attributes\":{\"last_analysis_date\":\(date),\"last_analysis_stats\":{\"malicious\":\(malicious),\"suspicious\":0,\"undetected\":70}}}}".utf8)
        }
        XCTAssertEqual(try VirusTotalReputation.parse(report(date: now.timeIntervalSince1970 - 30, malicious: 0), now: now).verdict, .checked)
        XCTAssertEqual(try VirusTotalReputation.parse(report(date: now.timeIntervalSince1970 - 86400 * 30, malicious: 0), now: now).verdict, .unknown)
        XCTAssertEqual(try VirusTotalReputation.parse(report(date: now.timeIntervalSince1970 - 30, malicious: 2), now: now).verdict, .concern)
        XCTAssertThrowsError(try VirusTotalReputation.parse(Data("{\"data\":{\"attributes\":{}}}".utf8), now: now))
        let timeouts = Data("{\"data\":{\"attributes\":{\"last_analysis_date\":1800000000,\"last_analysis_stats\":{\"malicious\":0,\"suspicious\":0,\"timeout\":70}}}}".utf8)
        XCTAssertThrowsError(try VirusTotalReputation.parse(timeouts, now: now))
    }
    func testProtectedPreviewIsCopyBlockedForMismatchAndCleaned() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = AttachmentCache(root: root)
        let path = try await cache.store(Data("%PDF-1.7\n".utf8), accountID: UUID(), attachmentID: UUID(), filename: "report.pdf")
        let preview = try await cache.securePreview(path, filename: "report.pdf", mimeType: "application/pdf")
        let original = try await cache.existing(path)
        XCTAssertNotEqual(preview, original)
        #if targetEnvironment(simulator)
        XCTAssertEqual(LocalMailProtection.finding(for: root).verdict, .unknown)
        #else
        XCTAssertEqual(LocalMailProtection.finding(for: root).verdict, .checked)
        #endif
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "escape"), withDestinationURL: outside)
        XCTAssertEqual(LocalMailProtection.finding(for: root).verdict, .unknown)
        do { _ = try await cache.securePreview(path, filename: "photo.jpg", mimeType: "image/jpeg"); XCTFail("Previewed mismatch") }
        catch { XCTAssertTrue(error is AttachmentPreviewError) }
        AttachmentPreviewStore.remove(preview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(original).path))
    }
}
