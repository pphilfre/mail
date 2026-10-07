import Foundation
import SwiftData

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low = "Low", normal = "Normal", high = "High", urgent = "Urgent"
    var id: String { rawValue }
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 1 }
    var symbol: String { self == .urgent ? "exclamationmark.2" : self == .high ? "arrow.up" : self == .low ? "arrow.down" : "minus" }
}
enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case toDo = "To do", inProgress = "In progress", done = "Done"
    var id: String { rawValue }
}
struct TaskStep: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var isCompleted = false
}

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
    var progress: TaskStatus = .toDo
    var priority: TaskPriority = .normal
    var steps: [TaskStep] = []
    var list = ""
    static let personalAccountID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    var isStandalone: Bool { accountID == Self.personalAccountID && remoteMessageID.isEmpty && remoteThreadID.isEmpty }
    var status: TaskStatus { isCompleted ? .done : progress == .done ? .toDo : progress }
    var accessibilityKey: String { isStandalone ? id.uuidString : remoteMessageID }
    static func standalone(title: String = "") -> MailTask {
        MailTask(accountID: personalAccountID, remoteMessageID: "", remoteThreadID: "", title: title, subject: "", sender: "")
    }
    mutating func move(to status: TaskStatus, now: Date = Date()) {
        progress = status == .done ? .toDo : status
        completedAt = status == .done ? (completedAt ?? now) : nil
    }
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

// Older email tasks keep their original identities and completion history.
extension MailTask {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        id = try c.decode(UUID.self, forKey: .id)
        accountID = try c.decode(UUID.self, forKey: .accountID)
        remoteMessageID = try c.decode(String.self, forKey: .remoteMessageID)
        remoteThreadID = try c.decode(String.self, forKey: .remoteThreadID)
        title = try c.decode(String.self, forKey: .title)
        subject = try c.decode(String.self, forKey: .subject)
        sender = try c.decode(String.self, forKey: .sender)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        progress = try c.decodeIfPresent(TaskStatus.self, forKey: .progress) ?? .toDo
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .normal
        steps = try c.decodeIfPresent([TaskStep].self, forKey: .steps) ?? []
        list = try c.decodeIfPresent(String.self, forKey: .list) ?? ""
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
        if !task.isStandalone { guard try account(id: task.accountID) != nil else { throw GmailError.reconnect } }
        var value = task
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty else { throw MailTaskError.emptyTitle }
        guard value.version == 1 else { throw MailTaskError.invalidData }
        guard value.accountID != MailTask.personalAccountID || value.isStandalone else { throw MailTaskError.invalidData }
        value.steps = value.steps.compactMap { step in
            var step = step; step.title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return step.title.isEmpty ? nil : step
        }
        value.list = value.list.trimmingCharacters(in: .whitespacesAndNewlines)
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
