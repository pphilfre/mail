import SwiftUI
import SwiftData
import Charts

private enum SenderProfileTab: String, CaseIterable, Identifiable {
    case mail = "Mail", files = "Files", tasks = "Tasks", receipts = "Receipts"
    var id: String { rawValue }
}

struct SenderProfileView: View {
    let email: String
    let name: String
    @Query private var messages: [MailMessage]
    @Query private var attachments: [MailAttachment]
    @Query private var metadata: [StoreMetadata]
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @State private var accountID: UUID?
    @State private var tab = SenderProfileTab.mail
    @State private var editingProfile = false
    @State private var editingTask: MailTask?
    @State private var detected: [UUID: ReceiptSummary] = [:]
    @State private var scanning = true
    init(email: String, name: String, initialAccountID: UUID?) {
        self.email = SenderInsights.normalise(email); self.name = name
        _accountID = State(initialValue: initialAccountID)
    }
    private var incoming: [MailMessage] { SenderInsights.received(messages, email: email, accountID: accountID) }
    private var outgoing: [MailMessage] { SenderInsights.sent(messages, email: email, accountID: accountID) }
    private var correspondence: [MailMessage] { incoming + outgoing }
    private var files: [MailAttachment] {
        let ids = Set(correspondence.map(\.id))
        return attachments.filter { ids.contains($0.messageID) }.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }
    private var tasks: [MailTask] {
        SenderInsights.linkedTasks(metadata.filter { $0.key.hasPrefix("mail-task:") }.compactMap { try? MailTask.decode($0) }, received: correspondence)
    }
    private var profileRow: StoreMetadata? { metadata.first { $0.key == SenderProfile.prefix + email } }
    private var profile: SenderProfile? { profileRow.flatMap { try? SenderProfile.decode($0) } }
    private var title: String {
        if let nickname = profile?.nickname, !nickname.isEmpty { return nickname }
        return name.isEmpty ? email : name
    }
    private var sources: [ReceiptSource] { incoming.map(ReceiptSource.init) }
    private var receipts: [ReceiptSummary] {
        let corrections = Dictionary(uniqueKeysWithValues: metadata.filter { $0.key.hasPrefix("receipt-override:") }.compactMap { row -> (String, ReceiptOverride)? in
            guard let value = try? ReceiptOverride.decode(row) else { return nil }
            return (row.key, value)
        })
        return sources.compactMap { source in
            if let correction = corrections[ReceiptOverride.prefix(source.accountID) + source.remoteID] {
                return correction.apply(to: source, detected: detected[source.id])
            }
            return detected[source.id]
        }
    }
    var body: some View {
        let snapshot = sources
        List {
            Section {
                HStack(spacing: 12) {
                    SenderAvatar(email: email, name: title)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title2.bold())
                        Text(email).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.padding(.vertical, 8)
                Picker("Account", selection: $accountID) {
                    Text("All accounts").tag(nil as UUID?)
                    ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
                }
                Text("Counts and history cover mail saved on this device. Spam, trash and drafts are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("At a glance") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { statistics }
                    VStack(alignment: .leading, spacing: 12) { statistics }
                }.padding(.vertical, 6)
                if let first = incoming.last?.receivedAt, let latest = incoming.first?.receivedAt {
                    LabeledContent("First received", value: first.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Latest received", value: latest.formatted(date: .abbreviated, time: .omitted))
                }
                if !incoming.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Received · last 8 weeks").font(.subheadline.weight(.semibold))
                        Chart(SenderInsights.activity(incoming)) { point in
                            BarMark(x: .value("Week", point.week, unit: .weekOfYear), y: .value("Messages", point.count))
                                .foregroundStyle(MailStyle.accent)
                                .accessibilityLabel("Week of \(point.week.formatted(date: .abbreviated, time: .omitted))")
                                .accessibilityValue("\(point.count) messages")
                        }.chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                            .frame(height: 130).accessibilityIdentifier("senderActivityChart")
                    }.padding(.vertical, 8)
                }
            }
            Section("Private notes") {
                if profileRow != nil && profile == nil {
                    Text(SenderProfileError.invalidData.localizedDescription).font(.caption).foregroundStyle(.secondary)
                } else if let notes = profile?.notes, !notes.isEmpty {
                    Text(notes).textSelection(.enabled)
                } else { Text("Keep useful details about this sender here.").foregroundStyle(.secondary) }
                Button("Edit nickname and notes", systemImage: "square.and.pencil") { editingProfile = true }
                    .disabled(profileRow != nil && profile == nil)
                    .accessibilityIdentifier("editSenderProfileButton")
            }
            Section {
                Picker("Profile content", selection: $tab) {
                    ForEach(SenderProfileTab.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("senderContentPicker")
            }
            content
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Sender profile").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingProfile) {
            let owners = Set((SenderInsights.received(messages, email: email, accountID: nil) +
                SenderInsights.sent(messages, email: email, accountID: nil)).map(\.accountID))
            NavigationStack {
                SenderProfileEditor(profile: profile ?? SenderProfile(email: email, accountIDs: Array(owners)), ownerIDs: owners)
            }
        }
        .sheet(item: $editingTask) { task in NavigationStack { MailTaskEditor(task: task) } }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let accountID, !ids.contains(accountID) { self.accountID = nil }
        }
        .task(id: snapshot) {
            scanning = true
            let values = await Task.detached(priority: .utility) {
                var results: [UUID: ReceiptSummary] = [:]
                for source in snapshot {
                    guard !Task.isCancelled else { break }
                    results[source.id] = ReceiptDetector.detect(source)
                }
                return results
            }.value
            guard !Task.isCancelled else { return }
            detected = values; scanning = false
        }
    }
    @ViewBuilder private var statistics: some View {
        statistic("Received", count: incoming.count)
        statistic("Sent to them", count: outgoing.count)
        statistic("Unread", count: incoming.filter { !$0.isRead }.count)
        statistic("Files", count: files.count)
    }
    private func statistic(_ label: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count, format: .number).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private var content: some View {
        switch tab {
        case .mail:
            Section("Conversation history") {
                ForEach(MailConversation.rows(correspondence, grouped: true)) { conversation in
                    NavigationLink { GmailMessageView(message: conversation.latest) } label: {
                        CachedMessageRow(message: conversation.latest, messageCount: conversation.messages.count,
                            unread: !conversation.isRead, starred: conversation.isStarred)
                    }
                }
                if correspondence.isEmpty { Text("No downloaded messages in this account.").foregroundStyle(.secondary) }
            }
            if !incoming.isEmpty {
                Section("Frequent subjects") {
                    ForEach(Array(SenderInsights.commonSubjects(incoming).prefix(3))) { subject in
                        LabeledContent(subject.subject, value: "\(subject.count)")
                    }
                }
            }
        case .files:
            Section("Files exchanged") {
                ForEach(files) { file in
                    VStack(alignment: .leading, spacing: 8) {
                        AttachmentRow(attachment: file)
                        if let source = correspondence.first(where: { $0.id == file.messageID }) {
                            NavigationLink { GmailMessageView(message: source) } label: {
                                Label(source.subject.isEmpty ? "Original email" : source.subject, systemImage: "envelope")
                            }.font(.subheadline)
                        }
                    }.padding(.vertical, 4)
                }
                if files.isEmpty { Text("No files in downloaded messages.").foregroundStyle(.secondary) }
            }
        case .tasks:
            Section("Linked tasks") {
                ForEach(tasks) { task in
                    Button { editingTask = task } label: {
                        Label(task.title, systemImage: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.primary)
                    }
                }
                if tasks.isEmpty { Text("Create a task from a conversation to see it here.").foregroundStyle(.secondary) }
            }
        case .receipts:
            Section("Receipts from this sender") {
                if scanning { ProgressView("Finding receipts…") }
                ForEach(receipts) { receipt in
                    if let source = incoming.first(where: { $0.id == receipt.id }) {
                        NavigationLink { GmailMessageView(message: source) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(receipt.subject).font(.headline)
                                Text(receipt.money?.display ?? "Amount not detected").font(.subheadline.monospacedDigit())
                                Text(receipt.reviewed ? "Reviewed" : "Detected · review in Receipts").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !scanning && receipts.isEmpty { Text("No receipts found in downloaded mail.").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct SenderProfileEditor: View {
    @State var profile: SenderProfile
    let ownerIDs: Set<UUID>
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Section {
                TextField("Nickname", text: $profile.nickname).accessibilityIdentifier("senderNicknameField")
                TextEditor(text: $profile.notes).frame(minHeight: 160).accessibilityIdentifier("senderNotesField")
            } header: { Text(profile.email) } footer: { Text("Private to this device. Notes are shared across your connected accounts for this sender.") }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Sender notes").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        guard let repository = runtime.repository else { throw GmailError.reconnect }
                        profile.accountIDs = Array(Set(profile.accountIDs).union(ownerIDs))
                        try repository.saveSenderProfile(profile); dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.accessibilityIdentifier("saveSenderProfileButton")
            }
        }
    }
}
