import XCTest
import UIKit
import SwiftUI
@testable import DispatchMail

@MainActor final class MailPolishTests: XCTestCase {
    func testWritingReviewMarksReplacementsAndApplyDoesNotAppend() {
        let original = "Please review tomorrow."
        let revised = "Please review today."
        let comparison = LocalWritingView.comparison(original: original, revised: revised)
        XCTAssertTrue(comparison.runs.contains { run in
            String(comparison.characters[run.range]).contains("tomorrow.") && run.foregroundColor == .red && run.strikethroughStyle == .single
        })
        XCTAssertTrue(comparison.runs.contains { run in
            String(comparison.characters[run.range]).contains("today.") && run.foregroundColor == .green && run.backgroundColor != nil
        })
        let view = UITextView()
        view.attributedText = RichMailEditor.attributed(original, document: nil)
        view.selectedRange = NSRange(location: original.utf16.count, length: 0)
        let controller = RichMailEditorController(); controller.view = view
        XCTAssertTrue(controller.applyRevision(revised, range: NSRange(location: 0, length: original.utf16.count), expected: original))
        XCTAssertEqual(view.text, revised)
    }

    func testGmailBodyDecodesMixedCaseSpacedCharsetWithoutDoubleDecoding() {
        let part = GmailPart(mimeType: "text/plain", headers: [
            GmailHeader(name: "Content-Type", value: "text/plain; CHARSET = 'windows-1252'; format=flowed"),
            GmailHeader(name: "Content-Transfer-Encoding", value: "quoted-printable")
        ], body: GmailBody(data: Base64URL.encode(Data([0x80, 0x32, 0x34]))))
        XCTAssertEqual(MailMIME.content(part).text.trimmingCharacters(in: .whitespacesAndNewlines), "€24")
        let literal = GmailPart(mimeType: "text/plain", body: GmailBody(data: Base64URL.encode(Data("Keep =20 as typed".utf8))))
        XCTAssertTrue(MailMIME.content(literal).text.contains("=20"))
    }
    func testRegistrableDomainRespectsCountryPrivateWildcardAndExceptionRules() {
        let list = MailPublicSuffixes(text: "com\nuk\nco.uk\nio\ngithub.io\n*.ck\n!www.ck")
        XCTAssertEqual(list.registrableDomain("news.example.co.uk"), "example.co.uk")
        XCTAssertEqual(list.registrableDomain("mail.alice.github.io"), "alice.github.io")
        XCTAssertEqual(list.registrableDomain("a.b.ck"), "a.b.ck")
        XCTAssertEqual(list.registrableDomain("a.www.ck"), "www.ck")
        XCTAssertNil(list.registrableDomain("co.uk"))
        XCTAssertEqual(SenderIdentity.iconDomains(email: "a@news.example.co.uk", suffixes: list), ["news.example.co.uk", "example.co.uk"])
        XCTAssertEqual(SenderIdentity.iconDomains(email: "a@gmail.com", suffixes: list), [])
        XCTAssertEqual(SenderIdentity.iconDomains(email: "a@127.0.0.1", suffixes: list), [])
        XCTAssertEqual(SenderIdentity.iconDomains(email: "a@https://example.com/path", suffixes: list), [])
        XCTAssertEqual(MailPublicSuffixes.bundled.registrableDomain("news.example.co.uk"), "example.co.uk")
    }

    func testSummaryInputKeepsBodiesInOrderAndRemovesDuplicateQuotes() throws {
        let first = MailSummarySource(sender: "Alex", subject: "Subject must not replace body", text: "Please submit the signed proposal by 12 October.", html: nil, receivedAt: Date(timeIntervalSince1970: 1))
        let second = MailSummarySource(sender: "Jamie", subject: "Re: Proposal", text: "The deadline is now 15 October.\n\n-- \nJamie\nOn Monday, Alex wrote:\n> Please submit the signed proposal by 12 October.", html: nil, receivedAt: Date(timeIntervalSince1970: 2))
        let inputs = try MailSummaryPreparation.inputs([second, first], maximum: 2_600)
        XCTAssertEqual(inputs.count, 2)
        XCTAssertTrue(inputs[0].contains("12 October"))
        XCTAssertTrue(inputs[1].contains("15 October"))
        XCTAssertFalse(inputs[1].contains("12 October"))
        XCTAssertTrue(inputs[0].contains("Subject must not replace body"), "Subjects supply context, but never replace missing bodies")
        XCTAssertFalse(inputs.joined().contains("Received:"))
        let single = try MailSummaryPreparation.inputs([second], maximum: 2_600)
        XCTAssertTrue(single.joined().contains("12 October"), "Keep context when the earlier message is absent")
    }

    func testLongHTMLInputIncludesFinalRequestAndNoHiddenPreheader() throws {
        let source = MailSummarySource(sender: "Finance", subject: "Invoice", text: nil,
            html: "<style>junk</style><div style=\"display:none\">Tracking preheader</div><p>" + String(repeating: "Background details. ", count: 800) + "</p><p>Please pay £245 by 15 October.</p>")
        let inputs = try MailSummaryPreparation.inputs([source], maximum: 2_600)
        XCTAssertGreaterThan(inputs.count, 1)
        XCTAssertTrue(inputs.allSatisfy { $0.count <= 2_600 })
        XCTAssertTrue(inputs.last?.contains("£245 by 15 October") == true)
        XCTAssertFalse(inputs.joined().contains("Tracking preheader"))
        XCTAssertThrowsError(try MailSummaryPreparation.inputs([.init(sender: "Alex", subject: "Only metadata", text: nil, html: nil)], maximum: 2_600))
    }

    func testEmbeddedImagesDoNotExhaustReadableBodyBudget() throws {
        let html = "<img src=\"data:image/png;base64," + String(repeating: "a", count: 2_100_000) + "\"><p>Please approve £45.</p>"
        let htmlOnly = MailSummarySource(sender: "Alex", subject: "Approval", text: nil, html: html)
        XCTAssertTrue(try MailSummaryPreparation.inputs([htmlOnly], maximum: 2_600).joined().contains("Please approve £45."))
        let plain = MailSummarySource(sender: "Alex", subject: "Approval", text: "Please approve £45.", html: html)
        XCTAssertEqual(try MailSummaryPreparation.inputs([plain], maximum: 2_600).count, 1)
    }

    func testSummaryReductionConsumesEveryChunkAndReturnsOneParagraph() async throws {
        var calls: [String] = []
        let result = try await MailSummaryPipeline.run(["First request", "Later agreement"], maximum: 500) { text in
            calls.append(text)
            if text == "First request" { return "• Alex requested approval." }
            if text == "Later agreement" { return "• Jamie approved the proposal." }
            return "Summary: Jamie approved Alex’s proposal.\nThe team can proceed."
        }
        XCTAssertEqual(calls.count, 3)
        XCTAssertTrue(calls[2].contains("Alex requested approval."))
        XCTAssertTrue(calls[2].contains("Jamie approved the proposal."))
        XCTAssertEqual(result, "Jamie approved Alex’s proposal. The team can proceed.")
    }

    func testSummaryFailureIsNotReplacedByAnExtractiveSuccess() async {
        do {
            _ = try await MailSummaryPipeline.run(["Readable body"], maximum: 500) { _ in throw LocalModelError.unavailable }
            XCTFail("Generation failure must be visible")
        } catch { XCTAssertEqual(error.localizedDescription, LocalModelError.unavailable.localizedDescription) }
    }

    func testAcceptedWritingPreservesOutsideFormattingAndRejectsStaleDraft() {
        let text = "😀 Please review.\nSignature"
        let view = UITextView()
        view.attributedText = RichMailEditor.attributed(text, document: RichMailBody(text: text, runs: [.init(location: 18, length: 9, bold: true)]))
        let controller = RichMailEditorController(); controller.view = view
        let range = (text as NSString).range(of: "Please review.")
        view.selectedRange = NSRange(location: text.utf16.count, length: 0)
        var changed = 0; controller.changed = { changed += 1 }
        XCTAssertTrue(controller.applyRevision("Please take a look.", range: range, expected: text))
        XCTAssertTrue(view.text.contains("😀 Please take a look.\nSignature"))
        XCTAssertEqual(view.selectedRange.location, view.text.utf16.count)
        XCTAssertEqual(changed, 1)
        XCTAssertFalse(controller.applyRevision("Stale", range: range, expected: text))
        let signature = (view.text as NSString).range(of: "Signature")
        XCTAssertTrue((view.textStorage.attribute(.font, at: signature.location, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    func testSecurityUnknownDoesNotBecomeGreen() {
        for status in [MailSecurityStatus.unknown, .lowRisk, .uncertain, .suspicious] {
            XCTAssertNotNil(UIImage(systemName: status.symbol), "Every security status needs a visible symbol")
        }
        XCTAssertEqual(MailSecurityStatus(report: nil), .unknown)
        XCTAssertEqual(MailSecurityStatus(report: SecurityReport(findings: [])), .unknown)
        XCTAssertEqual(MailSecurityStatus(report: SecurityReport(findings: [.init(id: "dkim", title: "DKIM", verdict: .unknown, explanation: "Not analysed")])), .unknown)
        XCTAssertEqual(MailSecurityStatus(report: SecurityReport(findings: [.init(id: "link", title: "Link", verdict: .concern, explanation: "Mismatch", points: 20)])), .uncertain)
        XCTAssertEqual(MailSecurityStatus(report: SecurityReport(findings: [.init(id: "link", title: "Link", verdict: .concern, explanation: "Suspicious", points: 50)])), .suspicious)
    }
}
