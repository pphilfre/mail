import XCTest
@testable import DispatchMail

final class MailSearchTests: XCTestCase {
    func testSearchAcrossFieldsAndAccountIsolation() {
        let first = UUID(), second = UUID()
        let newest = MailSearchDocument(id: UUID(), accountID: first,
            fields: ["Alex Morgan", "alex@example.com", "Project update", "Next week", "Freddie", "Work", "budget.pdf"])
        let older = MailSearchDocument(id: UUID(), accountID: second,
            fields: ["Jamie", "jamie@example.com", "Project update", "Next week", "Personal"])
        let index = MailSearchIndex(documents: [newest, older])
        XCTAssertEqual(index.matches("project"), [newest.id, older.id])
        XCTAssertEqual(index.matches("PROJECT", accountID: second), [older.id])
        XCTAssertEqual(index.matches("Alex budget"), [newest.id])
        XCTAssertEqual(index.matches("freddie work"), [newest.id])
        XCTAssertEqual(index.matches("example.com budget.pdf"), [newest.id])
        XCTAssertTrue(index.matches("jamie", accountID: first).isEmpty)
    }

    func testUnicodeWhitespaceAndShortTerms() {
        let row = MailSearchDocument(id: UUID(), accountID: nil, fields: ["José", "ＣＡＦＥ", "旅行", "a@example.com"])
        let index = MailSearchIndex(documents: [row])
        XCTAssertEqual(index.matches("  JOSE\n cafe  "), [row.id])
        XCTAssertEqual(index.matches("旅行"), [row.id])
        XCTAssertEqual(index.matches("a"), [row.id])
        XCTAssertTrue(index.matches(" \n ").isEmpty)
        XCTAssertTrue(index.matches("missing").isEmpty)
    }

    func testTrigramCandidatesRequireRealSubstring() {
        let row = MailSearchDocument(id: UUID(), accountID: nil, fields: ["abc bcd cde", "hello", "world"])
        let index = MailSearchIndex(documents: [row])
        XCTAssertTrue(index.matches("abcde").isEmpty)
        XCTAssertTrue(index.matches("lowo").isEmpty)
        XCTAssertEqual(index.matches("hello world"), [row.id])
    }

    func testTrashAndSpamAreExplicitlyOptIn() {
        let normal = MailSearchDocument(id: UUID(), accountID: nil, fields: ["Invoice"])
        let trash = MailSearchDocument(id: UUID(), accountID: nil, fields: ["Invoice"], isTrash: true)
        let spam = MailSearchDocument(id: UUID(), accountID: nil, fields: ["Invoice"], isSpam: true)
        let index = MailSearchIndex(documents: [normal, trash, spam])
        XCTAssertEqual(index.matches("invoice"), [normal.id])
        XCTAssertEqual(index.matches("invoice", includeTrashAndSpam: true), [normal.id, trash.id, spam.id])
    }

    func testRebuiltIndexRemovesDeletedAndChangedMetadata() {
        let id = UUID()
        let before = MailSearchIndex(documents: [MailSearchDocument(id: id, accountID: nil, fields: ["Old label"] )])
        let after = MailSearchIndex(documents: [MailSearchDocument(id: id, accountID: nil, fields: ["New label"] )])
        XCTAssertEqual(before.matches("old"), [id])
        XCTAssertTrue(after.matches("old").isEmpty)
        XCTAssertEqual(after.matches("new"), [id])
        XCTAssertTrue(MailSearchIndex().matches("label").isEmpty)
    }

    @MainActor func testCancelledBuildStopsBeforeIndexingDocuments() async {
        let document = MailSearchDocument(id: UUID(), accountID: nil, fields: ["Should not build"])
        // This task cannot start until the main actor yields; cancel it first.
        let work = Task { MailSearchIndex(documents: [document]) }
        work.cancel()
        let index = await work.value
        XCTAssertTrue(index.matches("build").isEmpty)
    }
}
