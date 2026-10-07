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
    @State private var quickTitle = ""
    @State private var query = ""
    @State private var onlyInProgress = false
    @State private var onlyToday = false
    @State private var selectedList = ""
    @FocusState private var quickFocused: Bool
    private var savedTasks: [MailTask] { taskRows.compactMap { try? MailTask.decode($0) } }
    private var taskRows: [StoreMetadata] {
        metadata.filter { row in
            guard row.key.hasPrefix("mail-task:") else { return false }
            guard let accountID else { return true }
            return row.key.hasPrefix(MailTask.prefix(accountID)) || row.key.hasPrefix(MailTask.prefix(MailTask.personalAccountID))
        }
    }
    private var tasks: [MailTask] {
        savedTasks.filter {
            (status == "All" || $0.isCompleted == completed) && (!onlyInProgress || $0.status == .inProgress) &&
            (!onlyToday || ["Overdue", "Today"].contains($0.section(now: Date()))) &&
            (selectedList.isEmpty || $0.list == selectedList) &&
            (query.isEmpty || [$0.title, $0.notes, $0.list].contains { $0.localizedCaseInsensitiveContains(query) })
        }
            .sorted {
                if completed { return ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                if $0.dueAt != $1.dueAt { return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
                if $0.priority != $1.priority { return $0.priority.rank > $1.priority.rank }
                return $0.createdAt < $1.createdAt
            }
    }
    var body: some View {
      TimelineView(.periodic(from: .now, by: 60)) { timeline in
        let snapshot = tasks
        let grouped = Dictionary(grouping: snapshot, by: { $0.section(now: timeline.date) })
        List {
            Section {
                VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Add a task", text: $quickTitle).submitLabel(.done).onSubmit(quickAdd)
                        .focused($quickFocused)
                        .accessibilityIdentifier("quickTaskTitle")
                    Button(action: quickAdd) {
                        Image(systemName: "plus").frame(width: 44, height: 44).contentShape(.rect)
                    }.buttonStyle(.borderless).accessibilityLabel("Add task").accessibilityIdentifier("quickAddTaskButton")
                        .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Picker("Tasks", selection: $status) {
                    Text("Open").tag("Open"); Text("All").tag("All"); Text("Completed").tag("Completed")
                }.pickerStyle(.segmented).accessibilityIdentifier("taskStatusFilter")
                }.accessibilityElement(children: .contain)
            }
                ForEach(completed ? ["Completed"] : ["Overdue", "Today", "Upcoming", "No due date"] + (status == "All" ? ["Completed"] : []), id: \.self) { section in
                    let rows = grouped[section] ?? []
                    if !rows.isEmpty {
                        Section(section) { ForEach(rows) { task in taskRow(task) } }
                    }
                }
            if snapshot.isEmpty {
                ContentUnavailableView(completed ? "No completed tasks" : "Your next step",
                    systemImage: "checklist", description: Text(completed ? "Tasks you finish will appear here." : "Add a task above or turn a conversation into a task. Use the plus button for dates, priorities and checklists."))
            }
            if taskRows.contains(where: { (try? MailTask.decode($0)) == nil }) {
                Text(MailTaskError.invalidData.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Tasks, notes or lists")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("Filter tasks", systemImage: "line.3.horizontal.decrease") {
                    Toggle("In progress", isOn: $onlyInProgress)
                    Toggle("Due today or overdue", isOn: $onlyToday)
                    Picker("List", selection: $selectedList) {
                        Text("All lists").tag("")
                        ForEach(Array(Set(savedTasks.map(\.list).filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New task", systemImage: "plus") { editing = .standalone() }
                    .accessibilityIdentifier("newTaskButton")
            }
        }
        .sheet(item: $editing) { task in NavigationStack { MailTaskEditor(task: task) } }
        .confirmationDialog("Delete this task?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete task", role: .destructive) {
                if let task = deleting { do { try runtime.repository?.deleteTask(task) } catch { errorMessage = error.localizedDescription } }
                deleting = nil
            }
        } message: { Text("This removes the task and its checklist. Any linked email stays in your mailbox.") }
      }
    }
    private func source(_ task: MailTask) -> MailMessage? {
        guard !task.isStandalone else { return nil }
        return messages.first { $0.accountID == task.accountID && $0.remoteID == task.remoteMessageID } ??
        messages.filter { $0.accountID == task.accountID && !task.remoteThreadID.isEmpty && $0.remoteThreadID == task.remoteThreadID }
            .max { $0.receivedAt < $1.receivedAt }
    }
    private func quickAdd() {
        let task = MailTask.standalone(title: quickTitle)
        guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            guard let repository = runtime.repository else { return }
            try repository.saveTask(task); quickTitle = ""; quickFocused = false; status = "Open"; query = ""
            onlyInProgress = false; onlyToday = false; selectedList = ""; feedback.select()
        } catch { errorMessage = error.localizedDescription }
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
                .accessibilityIdentifier("toggleTask-\(task.accessibilityKey)")
            VStack(alignment: .leading, spacing: 6) {
                Button { editing = task } label: { Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).multilineTextAlignment(.leading).lineLimit(2) }
                if !task.notes.isEmpty { Text(task.notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                HStack(spacing: 10) {
                    if task.status == .inProgress { Label("In progress", systemImage: "circle.lefthalf.filled").fixedSize() }
                    if task.priority != .normal { Label(task.priority.rawValue, systemImage: task.priority.symbol).fixedSize() }
                    if !task.steps.isEmpty { Label("\(task.steps.filter(\.isCompleted).count)/\(task.steps.count)", systemImage: "checklist").fixedSize() }
                }.font(.caption).foregroundStyle(.secondary)
                if !task.list.isEmpty { Label(task.list, systemImage: "folder").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let dueAt = task.dueAt {
                    Label(dueAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption).foregroundStyle(task.section(now: Date()) == "Overdue" ? .red : .secondary)
                }
                if !task.isStandalone { Text(accounts.first { $0.id == task.accountID }?.email ?? task.sender).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let message = source(task) {
                    NavigationLink { GmailMessageView(message: message) } label: { Label("Open conversation", systemImage: "envelope") }
                        .font(.caption).accessibilityIdentifier("taskConversation-\(task.remoteMessageID)")
                } else if !task.isStandalone { Text("Original message is no longer cached").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(TaskStatus.allCases) { value in
                    Button(value.rawValue) {
                        var valueTask = task; valueTask.move(to: value)
                        do { try runtime.repository?.saveTask(valueTask) } catch { errorMessage = error.localizedDescription }
                    }
                }
                Button("Edit task", systemImage: "pencil") { editing = task }
                Button("Delete task", systemImage: "trash", role: .destructive) { deleting = task }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(.rect)
            }.accessibilityLabel("Task actions")
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
    @State private var selectedStatus: TaskStatus
    @State private var newStep = ""
    init(task: MailTask) {
        _task = State(initialValue: task)
        _hasDueDate = State(initialValue: task.dueAt != nil)
        _dueDate = State(initialValue: task.dueAt ?? Date())
        _selectedStatus = State(initialValue: task.status)
    }
    var body: some View {
        Form {
            Section("Next step") {
                TextField("Task title", text: $task.title).accessibilityIdentifier("mailTaskTitle")
                TextEditor(text: $task.notes).frame(minHeight: 120).accessibilityLabel("Task notes").accessibilityIdentifier("mailTaskNotes")
            }
            Section {
                Picker("Status", selection: $selectedStatus) {
                    ForEach(TaskStatus.allCases) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("taskWorkflowPicker")
                Picker("Priority", selection: $task.priority) {
                    ForEach(TaskPriority.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }.accessibilityIdentifier("taskPriorityPicker")
                TextField("List (optional)", text: $task.list).accessibilityIdentifier("taskListField")
                Toggle("Due date", isOn: $hasDueDate).accessibilityIdentifier("mailTaskDueToggle")
                if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
            } footer: { Text("Due dates organise your task list. Tasks stay on this device.") }
            Section("Checklist") {
                ForEach($task.steps) { $step in
                    HStack {
                        Button { step.isCompleted.toggle() } label: {
                            Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Toggle \(step.title)")
                        TextField("Step", text: $step.title)
                    }
                }.onDelete { task.steps.remove(atOffsets: $0) }
                TextField("Add a step", text: $newStep).onSubmit(addStep).accessibilityIdentifier("newTaskStep")
                Button("Add step", systemImage: "plus", action: addStep).disabled(newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !task.isStandalone { Section("Conversation") {
                Text(task.subject.isEmpty ? "No subject" : task.subject)
                Text(task.sender).font(.caption).foregroundStyle(.secondary)
            } }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle(task.isStandalone ? "Task" : "Email task").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save task") {
                    task.dueAt = hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil
                    addStep(); task.move(to: selectedStatus)
                    do {
                        guard let repository = runtime.repository else { return }
                        try repository.saveTask(task); feedback.show("Task saved", symbol: "checklist"); dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveMailTaskButton")
            }
        }
    }
    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        task.steps.append(TaskStep(title: title)); newStep = ""
    }
}
