import SwiftUI
import SwiftData
import Charts

private enum SenderProfileTab: String, CaseIterable, Identifiable {
    case mail = "Mail", files = "Files", tasks = "Tasks", receipts = "Receipts"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .mail: "envelope"
        case .files: "paperclip"
        case .tasks: "checklist"
        case .receipts: "receipt"
        }
    }
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
    @State private var showingDetails = false
    @State private var composing = false
    init(email: String, name: String, initialAccountID: UUID?) {
        self.email = SenderInsights.normalise(email); self.name = name
        _accountID = State(initialValue: initialAccountID)
    }
    private var incoming: [MailMessage] { SenderInsights.received(messages, email: email, accountID: accountID) }
    private var outgoing: [MailMessage] { SenderInsights.sent(messages, email: email, accountID: accountID) }
    private var correspondence: [MailMessage] { incoming + outgoing }
    private var files: [MailAttachment] {
        let ids = Set(correspondence.map(\.id))
        return attachments.filter { ids.contains($0.messageID) && $0.contentID == nil }.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
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
            profileHeader
            content
            senderDetails
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .buttonStyle(.borderless)
        .navigationTitle("Sender profile").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingProfile) {
            let owners = Set((SenderInsights.received(messages, email: email, accountID: nil) +
                SenderInsights.sent(messages, email: email, accountID: nil)).map(\.accountID))
            NavigationStack {
                SenderProfileEditor(profile: profile ?? SenderProfile(email: email, accountIDs: Array(owners)), ownerIDs: owners)
            }
        }
        .sheet(isPresented: $composing) {
            NavigationStack { ComposeView(draft: LocalDraft(to: email, accountID: accountID)) }
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
    private var profileHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                SenderAvatar(email: email, name: title, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).lineLimit(2)
                    Text(email).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button { composing = true } label: {
                    Image(systemName: "square.and.pencil").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }.accessibilityLabel("Compose to sender")
                    .accessibilityIdentifier("senderComposeButton")
            }
            HStack(spacing: 16) {
                Text("\(incoming.count) received")
                Text("\(outgoing.count) sent")
                Label("\(incoming.filter { !$0.isRead }.count)", systemImage: "envelope.badge")
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                Menu {
                    Picker("Account", selection: $accountID) {
                        Text("All accounts").tag(nil as UUID?)
                        ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
                    }
                } label: {
                    Label(accounts.first { $0.id == accountID }?.displayName ?? "All accounts", systemImage: "person.crop.circle")
                        .font(.caption).lineLimit(1).frame(minHeight: 44)
                }
                Spacer()
                Button { editingProfile = true } label: {
                    Image(systemName: "note.text").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }.accessibilityLabel("Edit nickname and notes")
                    .disabled(profileRow != nil && profile == nil)
                    .accessibilityIdentifier("editSenderProfileButton")
            }
            if let notes = profile?.notes, !notes.isEmpty {
                Text(notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 4) {
                ForEach(SenderProfileTab.allCases) { value in
                    Button { tab = value } label: {
                        VStack(spacing: 4) {
                            Image(systemName: value.symbol).font(.system(size: 18, weight: .medium))
                            Text(tabCount(value), format: .number).font(.caption.monospacedDigit())
                    }.frame(maxWidth: .infinity, minHeight: 52).contentShape(.rect)
                            .background(tab == value ? MailStyle.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 14))
                    }.buttonStyle(.plain).foregroundStyle(tab == value ? MailStyle.accent : .secondary)
                        .accessibilityLabel(value.rawValue).accessibilityValue("\(tabCount(value))")
                        .accessibilityAddTraits(tab == value ? [.isSelected] : [])
                        .accessibilityIdentifier("senderTab-\(value.rawValue)")
                }
            }
            }.accessibilityElement(children: .contain)
        }
    }
    private var senderDetails: some View {
        Section {
            DisclosureGroup("Sender details", isExpanded: $showingDetails) {
                if profileRow != nil && profile == nil {
                    Text(SenderProfileError.invalidData.localizedDescription).font(.caption)
                }
                if let first = incoming.last?.receivedAt, let latest = incoming.first?.receivedAt {
                    LabeledContent("First received", value: first.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Latest received", value: latest.formatted(date: .abbreviated, time: .omitted))
                }
                if showingDetails && !incoming.isEmpty {
                    Chart(SenderInsights.activity(incoming)) { point in
                        BarMark(x: .value("Week", point.week, unit: .weekOfYear), y: .value("Messages", point.count))
                            .foregroundStyle(MailStyle.accent)
                    }.frame(height: 100).accessibilityIdentifier("senderActivityChart")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frequent subjects").font(.subheadline.weight(.semibold))
                        ForEach(Array(SenderInsights.commonSubjects(incoming).prefix(3))) { subject in
                            LabeledContent(subject.subject, value: "\(subject.count)")
                        }
                    }
                }
                Text("History covers mail saved on this device. Spam, trash and drafts are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
                if let notes = profile?.notes, !notes.isEmpty { Text(notes).textSelection(.enabled) }
            }
        }
    }
    private func tabCount(_ value: SenderProfileTab) -> Int {
        switch value {
        case .mail: MailConversation.rows(correspondence, grouped: true).count
        case .files: files.count
        case .tasks: tasks.filter { !$0.isCompleted }.count
        case .receipts: receipts.count
        }
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
