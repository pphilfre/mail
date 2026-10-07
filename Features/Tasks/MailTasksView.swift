import SwiftUI
import SwiftData

struct MailTasksView: View {
    let accountID: UUID?
    @Environment(AppRuntime.self) private var runtime
    @Environment(MailFeedback.self) private var feedback
    @Query private var metadata: [StoreMetadata]
    @Query private var messages: [MailMessage]
    @Query private var accounts: [MailAccount]
    @State private var status = "Open"
    private var completed: Bool { status == "Completed" }
    @State private var editing: MailTask?
    @State private var deleting: MailTask?
    @State private var errorMessage: String?
    private var taskRows: [StoreMetadata] {
        metadata.filter { $0.key.hasPrefix(accountID.map(MailTask.prefix) ?? "mail-task:") }
    }
    private var tasks: [MailTask] {
        taskRows.compactMap { try? MailTask.decode($0) }.filter { status == "All" || $0.isCompleted == completed }
            .sorted {
                if completed { return ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                if $0.dueAt != $1.dueAt { return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
                return $0.createdAt < $1.createdAt
            }
    }
    var body: some View {
      TimelineView(.periodic(from: .now, by: 60)) { timeline in
        List {
            Section {
                Picker("Tasks", selection: $status) {
                    Text("Open").tag("Open"); Text("All").tag("All"); Text("Completed").tag("Completed")
                }.pickerStyle(.segmented).accessibilityIdentifier("taskStatusFilter")
            }
                ForEach(completed ? ["Completed"] : ["Overdue", "Today", "Upcoming", "No due date"] + (status == "All" ? ["Completed"] : []), id: \.self) { section in
                    let rows = tasks.filter { $0.section(now: timeline.date) == section }
                    if !rows.isEmpty {
                        Section(section) { ForEach(rows) { task in taskRow(task) } }
                    }
                }
            if tasks.isEmpty {
                ContentUnavailableView(completed ? "No completed tasks" : "Turn mail into a next step",
                    systemImage: "checklist", description: Text(completed ? "Tasks you finish will appear here." : "Open a conversation and choose Make task. Add a note or due date to follow up later."))
            }
            if taskRows.contains(where: { (try? MailTask.decode($0)) == nil }) {
                Text(MailTaskError.invalidData.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { task in NavigationStack { MailTaskEditor(task: task) } }
        .confirmationDialog("Delete this task?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete task", role: .destructive) {
                if let task = deleting { do { try runtime.repository?.deleteTask(task) } catch { errorMessage = error.localizedDescription } }
                deleting = nil
            }
        } message: { Text("The original email stays in your mailbox.") }
      }
    }
    private func source(_ task: MailTask) -> MailMessage? {
        messages.first { $0.accountID == task.accountID && $0.remoteID == task.remoteMessageID } ??
        messages.filter { $0.accountID == task.accountID && !task.remoteThreadID.isEmpty && $0.remoteThreadID == task.remoteThreadID }
            .max { $0.receivedAt < $1.receivedAt }
    }
    private func taskRow(_ task: MailTask) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                var updated = task; updated.completedAt = task.isCompleted ? nil : Date()
                do { try runtime.repository?.saveTask(updated); feedback.select() }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(task.isCompleted ? MailStyle.success : MailStyle.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel(task.isCompleted ? "Reopen \(task.title)" : "Complete \(task.title)")
                .accessibilityIdentifier("toggleTask-\(task.remoteMessageID)")
            VStack(alignment: .leading, spacing: 6) {
                Button { editing = task } label: { Text(task.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading) }
                if !task.notes.isEmpty { Text(task.notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                if let dueAt = task.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption).foregroundStyle(task.section(now: Date()) == "Overdue" ? .red : .secondary)
                }
                Text(accounts.first { $0.id == task.accountID }?.email ?? task.sender).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let message = source(task) {
                    NavigationLink { GmailMessageView(message: message) } label: { Label("Open conversation", systemImage: "envelope") }
                        .font(.caption).accessibilityIdentifier("taskConversation-\(task.remoteMessageID)")
                } else { Text("Original message is no longer cached").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless).padding(.vertical, 5)
        .contextMenu {
            Button("Edit task", systemImage: "pencil") { editing = task }
            Button("Delete task", systemImage: "trash", role: .destructive) { deleting = task }
        }
    }
}

struct MailTaskEditor: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @State private var task: MailTask
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var errorMessage: String?
    init(task: MailTask) {
        _task = State(initialValue: task)
        _hasDueDate = State(initialValue: task.dueAt != nil)
        _dueDate = State(initialValue: task.dueAt ?? Date())
    }
    var body: some View {
        Form {
            Section("Next step") {
                TextField("Task title", text: $task.title).accessibilityIdentifier("mailTaskTitle")
                TextEditor(text: $task.notes).frame(minHeight: 120).accessibilityLabel("Task notes").accessibilityIdentifier("mailTaskNotes")
            }
            Section {
                Toggle("Due date", isOn: $hasDueDate).accessibilityIdentifier("mailTaskDueToggle")
                if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
            } footer: { Text("Due dates organise your task list. Tasks stay on this device.") }
            Section("Conversation") {
                Text(task.subject.isEmpty ? "No subject" : task.subject)
                Text(task.sender).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Email task").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save task") {
                    task.dueAt = hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil
                    do {
                        guard let repository = runtime.repository else { return }
                        try repository.saveTask(task); feedback.show("Task saved", symbol: "checklist"); dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveMailTaskButton")
            }
        }
    }
}
