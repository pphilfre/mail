import Foundation
import SwiftData
import XCTest
@testable import DispatchMail

@MainActor
final class StandaloneTaskTests: XCTestCase {
    func testStandaloneTaskPersistsWithoutAccountAndSurvivesAccountRemoval() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        var task = MailTask.standalone(title: "  Book a delivery  ")
        task.priority = .high; task.list = "  Home  "
        task.steps = [TaskStep(title: "Choose a date"), TaskStep(title: " ")]
        task.move(to: .inProgress)
        try repository.saveTask(task)
        let account = MailAccount(provider: .gmail, email: "me@example.com")
        repository.context.insert(account); try repository.context.save()
        try repository.removeAccountData(id: account.id)
        var saved = try MailTask.decode(XCTUnwrap(repository.metadata(task.key)))
        XCTAssertTrue(saved.isStandalone); XCTAssertEqual(saved.title, "Book a delivery")
        XCTAssertEqual(saved.status, .inProgress); XCTAssertEqual(saved.priority, .high)
        XCTAssertEqual(saved.steps.count, 1); XCTAssertEqual(saved.list, "Home")
        saved.move(to: .done); try repository.saveTask(saved)
        XCTAssertTrue(try MailTask.decode(XCTUnwrap(repository.metadata(task.key))).isCompleted)
        saved.move(to: .toDo); try repository.saveTask(saved)
        XCTAssertFalse(try MailTask.decode(XCTUnwrap(repository.metadata(task.key))).isCompleted)
        try repository.deleteTask(saved); XCTAssertNil(try repository.metadata(task.key))
    }
    func testExistingEmailTaskDecodesWithoutNewFields() throws {
        let task = MailTask(accountID: UUID(), remoteMessageID: "old", remoteThreadID: "thread", title: "Follow up", subject: "Email", sender: "sender@example.com")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        for key in ["progress", "priority", "steps", "list"] { json.removeValue(forKey: key) }
        let metadata = StoreMetadata(key: task.key, value: String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self))
        let decoded = try MailTask.decode(metadata)
        XCTAssertEqual(decoded.id, task.id); XCTAssertFalse(decoded.isStandalone)
        XCTAssertEqual(decoded.status, .toDo); XCTAssertEqual(decoded.priority, .normal)
        XCTAssertTrue(decoded.steps.isEmpty)
    }
    func testEmptyStandaloneTitleIsRejectedAndCompletionDateIsStable() throws {
        let container = try MailStorage.open(inMemory: true)
        let repository = MailRepository(context: container.mainContext)
        XCTAssertThrowsError(try repository.saveTask(.standalone(title: "  ")))
        var task = MailTask.standalone(title: "Pay bill")
        task.move(to: .done, now: Date(timeIntervalSince1970: 100))
        task.move(to: .done, now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(task.completedAt, Date(timeIntervalSince1970: 100))
    }
}
