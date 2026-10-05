import Foundation
import SwiftData
import XCTest
@testable import DispatchMail

@MainActor
final class SenderAndLibraryTests: XCTestCase {
    private func message(_ account: UUID, id: String, sender: String = "person@example.com", date: Date = Date(), subject: String = "Plans") -> MailMessage {
        MailMessage(accountID: account, remoteID: id, remoteThreadID: "shared-thread",
            sender: MailAddress(name: "Person", email: sender), subject: subject, snippet: "", receivedAt: date)
    }
    func testSenderHistoryNormalisesAddressAndScopesAccountsAndFolders() {
        let first = UUID(), second = UUID()
        let incoming = message(first, id: "one", sender: "Person@Example.com")
        let other = message(second, id: "one")
        let spam = message(first, id: "spam"), trash = message(first, id: "trash"), draft = message(first, id: "draft")
        spam.isSpam = true; trash.isTrash = true; draft.isDraft = true
        let sent = message(first, id: "sent", sender: "me@example.com")
        sent.isSent = true; sent.cc = [MailAddress(email: "PERSON@example.com")]
        let unrelated = message(first, id: "unrelated", sender: "me@example.com")
        unrelated.isSent = true; unrelated.to = [MailAddress(email: "another@example.com")]
        let rows = [incoming, other, spam, trash, draft, sent, unrelated]
        XCTAssertEqual(SenderInsights.received(rows, email: " person@example.com ", accountID: first).map(\.id), [incoming.id])
        XCTAssertEqual(SenderInsights.received(rows, email: "person@example.com", accountID: nil).count, 2)
        XCTAssertEqual(SenderInsights.sent(rows, email: "person@example.com", accountID: first).map(\.id), [sent.id])
        XCTAssertTrue(SenderInsights.sent(rows, email: "person@example.com", accountID: second).isEmpty)
        sent.cc = []; sent.bcc = [MailAddress(email: "person@example.com")]
        XCTAssertEqual(SenderInsights.sent(rows, email: "person@example.com", accountID: first).count, 1)
        sent.bcc = []; sent.to = [MailAddress(email: "person@example.com")]
        XCTAssertEqual(SenderInsights.sent(rows, email: "person@example.com", accountID: first).count, 1)
    }
    func testDirectoryGroupsAliasesByAddressAndUsesLatestNameAndUnreadCounts() {
        let account = UUID()
        let older = message(account, id: "one", date: Date(timeIntervalSince1970: 1000))
        let newer = message(account, id: "two", sender: "PERSON@example.com", date: Date(timeIntervalSince1970: 2000))
        newer.senderName = "New name"; newer.isRead = true
        let invalid = message(account, id: "invalid", sender: "not-an-address")
        let directory = SenderInsights.directory([older, newer, invalid], accountID: nil)
        XCTAssertEqual(directory.count, 1); XCTAssertEqual(directory.first?.email, "person@example.com")
        XCTAssertEqual(directory.first?.name, "New name"); XCTAssertEqual(directory.first?.receivedCount, 2)
        XCTAssertEqual(directory.first?.unreadCount, 1)
    }
    func testActivityIncludesEmptyWeeksAndExcludesFutureAndOldMail() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London")); calendar.firstWeekday = 2
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 18)))
        let currentWeek = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now)?.start)
        let earliest = try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: -7, to: currentWeek))
        let account = UUID()
        let rows = [message(account, id: "boundary", date: earliest), message(account, id: "today", date: now),
            message(account, id: "old", date: earliest.addingTimeInterval(-1)), message(account, id: "future", date: now.addingTimeInterval(60))]
        let activity = SenderInsights.activity(rows, now: now, calendar: calendar)
        XCTAssertEqual(activity.count, 8); XCTAssertEqual(activity.first?.week, earliest)
        XCTAssertEqual(activity.first?.count, 1); XCTAssertEqual(activity.last?.count, 1)
        XCTAssertEqual(activity.reduce(0) { $0 + $1.count }, 2)
        XCTAssertEqual(activity.filter { $0.count == 0 }.count, 6)
    }
    func testSubjectGroupingStripsRepeatedReplyPrefixesAndTasksRemainAccountScoped() {
        let first = UUID(), second = UUID()
        let mail = message(first, id: "one", subject: "Re: Fwd: Plans")
        let next = message(first, id: "two", subject: "Plans")
        XCTAssertEqual(SenderInsights.commonSubjects([mail, next]), [SenderSubjectCount(subject: "Plans", count: 2)])
        let linked = MailTask(accountID: first, remoteMessageID: "another", remoteThreadID: mail.remoteThreadID, title: "Follow up", subject: "", sender: "person@example.com")
        let other = MailTask(accountID: second, remoteMessageID: mail.remoteID, remoteThreadID: mail.remoteThreadID, title: "Other", subject: "", sender: "person@example.com")
        XCTAssertEqual(SenderInsights.linkedTasks([linked, other], received: [mail]).map(\.id), [linked.id])
        mail.remoteThreadID = ""
        XCTAssertTrue(SenderInsights.linkedTasks([linked], received: [mail]).isEmpty)
    }
    func testSenderNotesSurviveReopenAndAccountRemovalKeepsOtherOwners() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appending(path: "mail.sqlite")
        let container = try MailStorage.open(at: store), repository = MailRepository(context: container.mainContext)
        let first = MailAccount(provider: .gmail, email: "first@example.com"), second = MailAccount(provider: .gmail, email: "second@example.com")
        repository.context.insert(first); repository.context.insert(second); try repository.context.save()
        var profile = SenderProfile(email: "person@example.com", accountIDs: [first.id, second.id, UUID()])
        profile.nickname = "  Alex  "; profile.notes = "Prefers morning meetings"
        try repository.saveSenderProfile(profile)
        let reopened = try MailStorage.open(at: store), other = MailRepository(context: reopened.mainContext)
        let saved = try SenderProfile.decode(XCTUnwrap(other.metadata(profile.key)))
        XCTAssertEqual(saved.nickname, "Alex"); XCTAssertEqual(saved.notes, profile.notes)
        XCTAssertEqual(Set(saved.accountIDs), [first.id, second.id])
        try other.removeAccountData(id: first.id)
        XCTAssertEqual(try SenderProfile.decode(XCTUnwrap(other.metadata(profile.key))).accountIDs, [second.id])
        try other.removeAccountData(id: second.id)
        XCTAssertNil(try other.metadata(profile.key))
    }
    func testDamagedProfileCannotBeSilentlyOverwritten() throws {
        let container = try MailStorage.open(inMemory: true), repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        let profile = SenderProfile(email: "person@example.com", accountIDs: [account.id])
        let damaged = StoreMetadata(key: profile.key, value: "saved-but-unreadable-notes")
        repository.context.insert(damaged); try repository.context.save()
        XCTAssertThrowsError(try repository.saveSenderProfile(profile))
        XCTAssertEqual(try repository.metadata(profile.key)?.value, "saved-but-unreadable-notes")
    }
    private func file(_ id: String, account: UUID?, filename: String, bytes: Int, date: Double = 1000, inline: Bool = false) -> AttachmentCatalogEntry {
        AttachmentCatalogEntry(id: id, accountID: account, attachmentID: UUID(), messageID: UUID(), draftID: nil,
            filename: filename, mimeType: "application/octet-stream", byteCount: bytes, sourceTitle: "Project plans",
            correspondent: "person@example.com", accountName: "me@example.com", date: Date(timeIntervalSince1970: date), inlineImage: inline, cachedPath: nil)
    }
    func testLibrarySearchFiltersOfflineFilesAndAccountScope() {
        let first = UUID(), second = UUID()
        let pdf = file("pdf", account: first, filename: "plans.PDF", bytes: 20)
        let logo = file("logo", account: first, filename: "logo.png", bytes: 100, inline: true)
        let other = file("other", account: second, filename: "plans.pdf", bytes: 200)
        let rows = [pdf, logo, other]
        XCTAssertEqual(AttachmentCatalogEntry.filtered(rows, accountID: first, query: " PERSON@EXAMPLE ", category: .documents,
            includeInline: false, savedOnly: true, savedIDs: [pdf.id, other.id], sort: .newest).map(\.id), [pdf.id])
        XCTAssertTrue(AttachmentCatalogEntry.filtered(rows, accountID: first, query: "", category: .images,
            includeInline: false, savedOnly: false, savedIDs: [], sort: .newest).isEmpty)
        XCTAssertEqual(AttachmentCatalogEntry.filtered(rows, accountID: first, query: "", category: .images,
            includeInline: true, savedOnly: false, savedIDs: [], sort: .newest).map(\.id), [logo.id])
    }
    func testLibraryClassifiesUnknownMimeTypesAndSortsDeterministically() {
        XCTAssertEqual(AttachmentCategory.classify(filename: "photo.HEIC", mimeType: "application/octet-stream"), .images)
        XCTAssertEqual(AttachmentCategory.classify(filename: "data", mimeType: "text/csv"), .documents)
        XCTAssertEqual(AttachmentCategory.classify(filename: "files.ZIP", mimeType: "application/octet-stream"), .archives)
        XCTAssertEqual(AttachmentCategory.classify(filename: "audio.mp3", mimeType: "audio/mpeg"), .other)
        let rows = [file("b", account: nil, filename: "file10.txt", bytes: 30, date: 3000),
            file("a", account: nil, filename: "file2.txt", bytes: 40), file("c", account: nil, filename: "file2.txt", bytes: 40)]
        func ids(_ sort: AttachmentSort) -> [String] {
            AttachmentCatalogEntry.filtered(rows, accountID: nil, query: "", category: .all, includeInline: true,
                savedOnly: false, savedIDs: [], sort: sort).map(\.id)
        }
        XCTAssertEqual(ids(.largest), ["a", "c", "b"]); XCTAssertEqual(ids(.name), ["a", "c", "b"])
        XCTAssertEqual(ids(.newest), ["b", "a", "c"])
    }
}
