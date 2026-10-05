import Foundation
import SwiftData
import XCTest
@testable import DispatchMail

@MainActor
final class CollectionAndSubscriptionTests: XCTestCase {
    private func message(_ account: UUID, id: String, subject: String = "Weekly newsletter", date: Date = Date()) -> MailMessage {
        MailMessage(accountID: account, remoteID: id, remoteThreadID: "shared-thread",
            sender: MailAddress(name: "Weekly news", email: "news@example.com"), subject: subject, snippet: "", receivedAt: date)
    }
    func testCollectionMembershipIncludesFutureThreadMessagesAndIsAccountScoped() {
        let first = UUID(), second = UUID()
        let source = message(first, id: "source"), reply = message(first, id: "reply"), other = message(second, id: "source")
        let spam = message(first, id: "spam"), trash = message(first, id: "trash"), draft = message(first, id: "draft")
        spam.isSpam = true; trash.isTrash = true; draft.isDraft = true
        let collection = MailCollection(name: "Trip", links: [MailCollectionLink(source)])
        let rows = collection.messages(in: [source, reply, other, spam, trash, draft], accountID: nil)
        XCTAssertEqual(Set(rows.map(\.id)), [source.id, reply.id])
        XCTAssertTrue(collection.messages(in: [source, reply, other], accountID: second).isEmpty)
        source.remoteThreadID = ""
        let single = MailCollection(name: "Single", links: [MailCollectionLink(source)])
        XCTAssertEqual(single.messages(in: [source, reply], accountID: nil).map(\.id), [source.id])
    }
    func testCollectionReopensDeduplicatesThreadsAndDeletionKeepsMail() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appending(path: "mail.sqlite")
        let container = try MailStorage.open(at: store), repository = MailRepository(context: container.mainContext)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account)
        let source = message(account.id, id: "source"), reply = message(account.id, id: "reply")
        repository.context.insert(source); repository.context.insert(reply); try repository.context.save()
        let collection = MailCollection(name: "  Trip  ", notes: "Bookings", links: [MailCollectionLink(source), MailCollectionLink(reply)])
        try repository.saveCollection(collection)
        let reopened = try MailStorage.open(at: store), other = MailRepository(context: reopened.mainContext)
        let saved = try MailCollection.decode(XCTUnwrap(other.metadata(collection.key)))
        XCTAssertEqual(saved.name, "Trip"); XCTAssertEqual(saved.notes, "Bookings"); XCTAssertEqual(saved.links.count, 1)
        try other.deleteCollection(saved)
        XCTAssertNil(try other.metadata(saved.key))
        XCTAssertNotNil(try other.message(accountID: account.id, remoteID: source.remoteID))
        XCTAssertTrue(try other.context.fetch(FetchDescriptor<PendingMailOperation>()).isEmpty)
    }
    func testRemovingAccountClearsOnlyItsCollectionLinksAndNewsletterChoices() throws {
        let container = try MailStorage.open(inMemory: true), repository = MailRepository(context: container.mainContext)
        let first = MailAccount(provider: .gmail, email: "first@example.com"), second = MailAccount(provider: .gmail, email: "second@example.com")
        repository.context.insert(first); repository.context.insert(second); try repository.context.save()
        let one = message(first.id, id: "one"), two = message(second.id, id: "two")
        let collection = MailCollection(name: "Project", links: [MailCollectionLink(one), MailCollectionLink(two)])
        try repository.saveCollection(collection)
        try repository.setSubscription(email: "NEWS@example.com", included: true, accountIDs: [first.id, second.id])
        try repository.removeAccountData(id: first.id)
        let saved = try MailCollection.decode(XCTUnwrap(repository.metadata(collection.key)))
        XCTAssertEqual(saved.links.map(\.accountID), [second.id])
        XCTAssertNil(try repository.metadata(SubscriptionRule.prefix(first.id) + "news@example.com"))
        XCTAssertNotNil(try repository.metadata(SubscriptionRule.prefix(second.id) + "news@example.com"))
        try repository.removeAccountData(id: second.id)
        XCTAssertTrue(try MailCollection.decode(XCTUnwrap(repository.metadata(collection.key))).links.isEmpty)
    }
    func testCollectionRejectsEmptyNameMissingAccountsAndDamagedSavedData() throws {
        let container = try MailStorage.open(inMemory: true), repository = MailRepository(context: container.mainContext)
        XCTAssertThrowsError(try repository.saveCollection(MailCollection(name: "  ")))
        let missing = MailCollection(name: "Missing", links: [MailCollectionLink(message(UUID(), id: "one"))])
        XCTAssertThrowsError(try repository.saveCollection(missing))
        let damaged = MailCollection(name: "Damaged")
        repository.context.insert(StoreMetadata(key: damaged.key, value: "unreadable-data")); try repository.context.save()
        XCTAssertThrowsError(try repository.saveCollection(damaged))
        XCTAssertEqual(try repository.metadata(damaged.key)?.value, "unreadable-data")
    }
    func testNewsletterSuggestionsRespectManualRulesAndAccountScope() {
        let first = UUID(), second = UUID()
        let one = message(first, id: "one"), two = message(second, id: "two")
        let spam = message(first, id: "spam"), sent = message(first, id: "sent")
        spam.isSpam = true; sent.isSent = true
        let rule = SubscriptionRule(accountID: first, email: "news@example.com", included: false)
        let entries = SubscriptionInsights.entries([one, two, spam, sent], rules: [rule], accountID: nil)
        XCTAssertEqual(entries.count, 1); XCTAssertEqual(entries.first?.messages.map(\.id), [two.id])
        XCTAssertTrue(SubscriptionInsights.entries([one, two], rules: [rule], accountID: first).isEmpty)
        let personal = message(first, id: "personal", subject: "Lunch plans")
        personal.senderName = "Alex"
        XCTAssertFalse(SubscriptionInsights.likelyNewsletter(personal))
        let include = SubscriptionRule(accountID: first, email: "news@example.com", included: true)
        XCTAssertTrue(SubscriptionInsights.entries([personal], rules: [include], accountID: first).first?.manuallyIncluded == true)
        personal.cachedText = Data("Order receipt\nTotal £20\nUnsubscribe".utf8); personal.subject = "Your receipt"
        XCTAssertFalse(SubscriptionInsights.likelyNewsletter(personal))
    }
    func testSubscriptionWeekCountsExcludeFutureMessagesAndPreferencesReset() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12)))
        let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: now))
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        let rows = [message(account.id, id: "start", date: start), message(account.id, id: "now", date: now),
            message(account.id, id: "old", date: start.addingTimeInterval(-1)), message(account.id, id: "future", date: now.addingTimeInterval(60))]
        XCTAssertEqual(SubscriptionInsights.entries(rows, rules: [], accountID: account.id, now: now, calendar: calendar).first?.weeklyCount, 2)
        let container = try MailStorage.open(inMemory: true), repository = MailRepository(context: container.mainContext)
        repository.context.insert(account); try repository.context.save()
        try repository.setSubscription(email: "news@example.com", included: false, accountIDs: [account.id])
        XCTAssertFalse(try SubscriptionRule.decode(XCTUnwrap(repository.metadata(SubscriptionRule.prefix(account.id) + "news@example.com"))).included)
        try repository.setSubscription(email: "news@example.com", included: nil, accountIDs: [account.id])
        XCTAssertNil(try repository.metadata(SubscriptionRule.prefix(account.id) + "news@example.com"))
    }
}
