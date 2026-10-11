import Foundation
import SwiftData
import UIKit
import XCTest
@testable import DispatchMail

@MainActor final class PremiumMailTests: XCTestCase {
    func testRichBodyEscapesTextAndAttributesAndRejectsActiveLinks() throws {
        let body = RichMailBody(text: "Hello <&> world", runs: [
            .init(location: 0, length: 5, bold: true, italic: true, underline: true, link: "javascript:alert(1)"),
            .init(location: 10, length: 5, link: "https://example.com/?a=1&b=2")
        ])
        let html = try XCTUnwrap(body.html(matching: body.text))
        XCTAssertTrue(html.contains("<strong>Hello</strong>"))
        XCTAssertTrue(html.contains("&lt;&amp;&gt;"))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("a=1&amp;b=2"))
        XCTAssertNil(body.html(matching: "Edited after formatting"))
    }
    func testUTF16FormattingAndListsProduceAccessibleHTML() throws {
        let body = RichMailBody(text: "😀 café\n• First\n• Second\n1. One\n2. Two", runs: [
            .init(location: 3, length: 4, bold: true),
            .init(location: Int.max, length: 10, italic: true),
            .init(location: -1, length: 1, underline: true)
        ])
        let html = try XCTUnwrap(body.html(matching: body.text))
        XCTAssertTrue(html.contains("😀 <strong>café</strong>"))
        XCTAssertTrue(html.contains("<ul><li>First</li><li>Second</li></ul>"))
        XCTAssertTrue(html.contains("<ol><li>One</li><li>Two</li></ol>"))
    }
    func testFormattingSurvivesStoreReopenAndDiscardWithoutSchemaChange() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "mail.sqlite")
        let container = try MailStorage.open(at: url)
        let repository = MailRepository(context: container.mainContext)
        let session = AppSession(draftStore: repository)
        var original = LocalDraft(body: "Keep this")
        original.richBody = RichMailBody(text: original.body, runs: [.init(location: 0, length: 4, bold: true)])
        try session.save(original)
        let reopened = try MailStorage.open(at: url)
        XCTAssertEqual(try MailRepository(context: reopened.mainContext).load().first?.richBody, original.richBody)
        let editor = DraftEditingSession(draft: original, alreadySaved: true)
        var changed = original; changed.richBody = RichMailBody(text: original.body, runs: [.init(location: 0, length: 4, italic: true)])
        try editor.checkpoint(changed, session: session)
        try editor.discard(session: session)
        XCTAssertEqual(try repository.load().first?.richBody, original.richBody)
        try session.deleteDraft(id: original.id)
        XCTAssertNil(try repository.metadata("draft-rich-body:\(original.id.uuidString)"))
    }
    func testRichMIMEContainsBothAlternativesAndAttachmentBytes() throws {
        var draft = LocalDraft(to: "other@example.com", body: "Hello\n• Review")
        draft.richBody = RichMailBody(text: draft.body, runs: [.init(location: 0, length: 5, bold: true)])
        let raw = try MailMIME.raw(draft, from: "me@example.com")
        let mime = try XCTUnwrap(String(data: XCTUnwrap(Base64URL.decode(raw)), encoding: .utf8))
        XCTAssertTrue(mime.contains("multipart/alternative"))
        XCTAssertTrue(mime.contains("text/plain; charset=UTF-8"))
        XCTAssertTrue(mime.contains("text/html; charset=UTF-8"))
        let file = DraftAttachment(id: UUID(), filename: "notes.txt", mimeType: "text/plain", byteCount: 3, sha256: "")
        draft.attachments = [file]
        let mixed = try MailMIME.raw(draft, from: "me@example.com", attachments: [.init(filename: file.filename, mimeType: file.mimeType, data: Data([1, 2, 3]))])
        let mixedMIME = try XCTUnwrap(String(data: XCTUnwrap(Base64URL.decode(mixed)), encoding: .utf8))
        XCTAssertTrue(mixedMIME.contains("multipart/mixed"))
        XCTAssertTrue(mixedMIME.contains("multipart/alternative"))
        XCTAssertTrue(mixedMIME.contains("AQID"))
        let fixture = URL.applicationSupportDirectory.appending(path: "Dispatch/rich-compose-mime-fixture.eml")
        try FileManager.default.createDirectory(at: fixture.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(mixedMIME.utf8).write(to: fixture, options: .atomic)
    }
    func testSummaryExtractsHTMLOnlyBodiesAndRetainsLateDeadlines() {
        let source = MailSummarySource(sender: "Alex", subject: "Update", text: " ", html: "<style>fake</style><p>Project approved.</p><p>Please submit by 12 October.</p>")
        let extracted = MailSummaryPreparation.body(source)
        XCTAssertTrue(extracted.contains("Project approved."))
        XCTAssertTrue(extracted.contains("12 October"))
        XCTAssertFalse(extracted.contains("fake"))
        let long = String(repeating: "Opening details. ", count: 1_000) + "\nSubmit by 12 October."
        let chunks = MailSummaryPreparation.chunks(long)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.last?.contains("12 October") == true)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 5_000 })
        XCTAssertEqual(chunks.joined().replacingOccurrences(of: "\n", with: ""), long.replacingOccurrences(of: "\n", with: ""))
        XCTAssertTrue(MailSummaryPreparation.body(.init(sender: "Alex", subject: "Subject only", text: nil, html: nil)).isEmpty)
    }
    func testNativeEditorRestoresStylesAndFormattingChangesReachDraftBinding() {
        let document = RichMailBody(text: "Keep me", runs: [.init(location: 0, length: 4, bold: true, underline: true)])
        let attributed = RichMailEditor.attributed(document.text, document: document)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertEqual(attributed.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        let view = UITextView(); view.attributedText = attributed; view.selectedRange = NSRange(location: 0, length: 4)
        let controller = RichMailEditorController(); controller.view = view
        var changes = 0; controller.changed = { changes += 1 }
        controller.toggleTrait(.traitItalic)
        XCTAssertEqual(changes, 1)
        XCTAssertTrue((view.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
    }
}
