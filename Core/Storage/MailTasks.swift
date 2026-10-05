import Foundation
import SwiftData

struct MailTask: Identifiable, Codable, Equatable, Sendable {
    var version = 1
    var id = UUID()
    let accountID: UUID
    let remoteMessageID: String
    let remoteThreadID: String
    var title: String
    let subject: String
    let sender: String
    var notes = ""
    var dueAt: Date?
    var completedAt: Date?
    var createdAt = Date()
    var updatedAt = Date()
    var isCompleted: Bool { completedAt != nil }
    static func prefix(_ accountID: UUID) -> String { "mail-task:\(accountID.uuidString):" }
    var key: String { Self.prefix(accountID) + id.uuidString }
    func section(now: Date, calendar: Calendar = .current) -> String {
        if isCompleted { return "Completed" }
        guard let dueAt else { return "No due date" }
        if dueAt < calendar.startOfDay(for: now) { return "Overdue" }
        if calendar.isDate(dueAt, inSameDayAs: now) { return "Today" }
        return "Upcoming"
    }
    static func decode(_ metadata: StoreMetadata) throws -> MailTask {
        let task = try JSONDecoder().decode(MailTask.self, from: Data(metadata.value.utf8))
        guard task.version == 1, task.key == metadata.key else { throw MailTaskError.invalidData }
        return task
    }
}

enum MailTaskError: LocalizedError {
    case emptyTitle, invalidData
    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Give this task a title."
        case .invalidData: "A saved task could not be read. Its saved data has been kept."
        }
    }
}

@MainActor extension MailRepository {
    func task(for message: MailMessage) throws -> MailTask {
        let tasks = try context.fetch(FetchDescriptor<StoreMetadata>()).filter { $0.key.hasPrefix(MailTask.prefix(message.accountID)) }
            .map { try MailTask.decode($0) }
        // One open task per conversation; completed tasks remain in the history.
        if let existing = tasks.first(where: { !$0.isCompleted &&
            ($0.remoteMessageID == message.remoteID || (!message.remoteThreadID.isEmpty && $0.remoteThreadID == message.remoteThreadID)) }) {
            return existing
        }
        return MailTask(accountID: message.accountID, remoteMessageID: message.remoteID,
            remoteThreadID: message.remoteThreadID, title: message.subject.isEmpty ? "Follow up" : message.subject,
            subject: message.subject, sender: message.senderEmail)
    }
    func saveTask(_ task: MailTask) throws {
        guard try account(id: task.accountID) != nil else { throw GmailError.reconnect }
        var value = task
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty else { throw MailTaskError.emptyTitle }
        guard value.version == 1 else { throw MailTaskError.invalidData }
        value.updatedAt = Date()
        try context.transaction {
            try setMetadata(value.key, value: String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
            try context.save()
        }
    }
    func deleteTask(_ task: MailTask) throws {
        try context.transaction { try setMetadata(task.key, value: nil); try context.save() }
    }
}
