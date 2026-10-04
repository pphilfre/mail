import XCTest
@testable import DispatchMail

final class MailSearchTests: XCTestCase {
    func testSavedSearchRoundTripsItsScopeAndFiltersAndRejectsUnknownVersions() {
        let row = SavedMailSearch(name: "Work files", query: "from:alex", accountID: UUID(),
            includeTrashAndSpam: false, filters: MailSearchFilters(unread: true, attachments: true))
        XCTAssertEqual(SavedMailSearch.decode(SavedMailSearch.encode([row])), [row])
        var future = row; future.version = 2
        XCTAssertEqual(SavedMailSearch.decode(SavedMailSearch.encode([row, future])), [row])
        XCTAssertTrue(SavedMailSearch.decode("not json").isEmpty)
        let index = MailSearchIndex(documents: [MailSearchDocument(id: UUID(), accountID: nil, fields: ["from:alex"])])
        XCTAssertEqual(index.matches(#""from:alex""#).count, 1)
    }
    func testTypedOperatorsPhrasesFiltersAndAccountIsolation() {
        let account = UUID()
        let document = MailSearchDocument(id: UUID(), accountID: account, fields: ["Café project plan", "Alex"],
            sender: "Alex alex@example.com", recipients: ["me@example.com"], subject: "Café project plan",
            labels: ["Work"], receivedAt: Date(timeIntervalSince1970: 1_780_000_000),
            isRead: false, isStarred: true, hasAttachments: true)
        let other = MailSearchDocument(id: UUID(), accountID: UUID(), fields: ["project plan"])
        let index = MailSearchIndex(documents: [document, other])
        XCTAssertEqual(index.matches(#"from:alex to:me subject:"cafe project" label:work is:unread has:attachment after:2026-01-01 before:2027-01-01"#), [document.id])
        XCTAssertEqual(index.matches(#""project plan""#, accountID: account), [document.id])
        XCTAssertEqual(index.matches("", filters: MailSearchFilters(unread: true, attachments: true)), [document.id])
        XCTAssertTrue(index.matches("is:read", accountID: account).isEmpty)
        XCTAssertTrue(index.matches("from:alex", accountID: other.accountID).isEmpty)
        XCTAssertTrue(index.matches("before:2026-02-30").isEmpty)
        XCTAssertNotNil(MailSearchQuery("before:2026-02-30").error)
        XCTAssertNotNil(MailSearchQuery(#"subject:"unfinished"#).error)
        XCTAssertNotNil(MailSearchQuery("from:").error)
        XCTAssertNotNil(MailSearchQuery("is:unknown").error)
    }
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
