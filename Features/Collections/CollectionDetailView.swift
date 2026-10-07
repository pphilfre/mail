import SwiftUI
import SwiftData

private enum CollectionTab: String, CaseIterable, Identifiable {
    case mail = "Mail", files = "Files", tasks = "Tasks", receipts = "Receipts"
    var id: String { rawValue }
}

struct CollectionDetailView: View {
    let collectionID: UUID
    let accountID: UUID?
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @Query private var metadata: [StoreMetadata]
    @Query private var messages: [MailMessage]
    @Query private var attachments: [MailAttachment]
    @State private var tab = CollectionTab.mail
    @State private var editing: MailCollection?
    @State private var adding = false
    @State private var deleting = false
    @State private var editingTask: MailTask?
    @State private var errorMessage: String?
    @State private var detected: [UUID: ReceiptSummary] = [:]
    @State private var scanning = true
    private var collection: MailCollection? {
        metadata.first { $0.key == MailCollection.prefix + collectionID.uuidString }.flatMap { try? MailCollection.decode($0) }
    }
    private var mail: [MailMessage] { collection?.messages(in: messages, accountID: accountID) ?? [] }
    private var files: [MailAttachment] {
        let ids = Set(mail.map(\.id))
        return attachments.filter { ids.contains($0.messageID) }.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }
    private var tasks: [MailTask] {
        SenderInsights.linkedTasks(metadata.filter { $0.key.hasPrefix("mail-task:") }.compactMap { try? MailTask.decode($0) }, received: mail)
    }
    private var sources: [ReceiptSource] { mail.filter { !$0.isSent }.map(ReceiptSource.init) }
    private var receipts: [ReceiptSummary] {
        let corrections = Dictionary(uniqueKeysWithValues: metadata.filter { $0.key.hasPrefix("receipt-override:") }.compactMap { row -> (String, ReceiptOverride)? in
            guard let value = try? ReceiptOverride.decode(row) else { return nil }; return (row.key, value)
        })
        return sources.compactMap { source in
            if let correction = corrections[ReceiptOverride.prefix(source.accountID) + source.remoteID] {
                return correction.apply(to: source, detected: detected[source.id])
            }
            return detected[source.id]
        }.sorted { $0.receivedAt > $1.receivedAt }
    }
    var body: some View {
        let snapshot = sources
        List {
            if let collection {
                Section {
                    if !collection.notes.isEmpty { Text(collection.notes).textSelection(.enabled) }
                    Text("\(mail.count) downloaded messages · \(files.count) files · \(tasks.count) tasks")
                        .font(.caption).foregroundStyle(.secondary)
                    if accountID != nil { Text("Showing the selected account.").font(.caption).foregroundStyle(.secondary) }
                    Button("Add conversations", systemImage: "plus") { adding = true }.accessibilityIdentifier("addCollectionMailButton")
                    Picker("Collection content", selection: $tab) { ForEach(CollectionTab.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).accessibilityIdentifier("collectionContentPicker")
                }
                content
            } else { ContentUnavailableView("Collection unavailable", systemImage: "folder", description: Text("It may have been removed, or its saved data could not be read.")) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle(collection?.name ?? "Collection")
        .toolbar { ToolbarItem(placement: .primaryAction) {
            if let collection {
                Menu("Collection options", systemImage: "ellipsis.circle") {
                    Button("Edit name and notes") { editing = collection }
                    Button("Delete collection", role: .destructive) { deleting = true }
                }
            }
        } }
        .sheet(item: $editing) { collection in NavigationStack { CollectionEditor(collection: collection) } }
        .sheet(item: $editingTask) { task in NavigationStack { MailTaskEditor(task: task) } }
        .sheet(isPresented: $adding) { NavigationStack { CollectionMembershipView(collectionID: collectionID, accountID: accountID) } }
        .confirmationDialog("Delete this collection?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete collection", role: .destructive) {
                do {
                    guard let collection, let repository = runtime.repository else { throw GmailError.reconnect }
                    try repository.deleteCollection(collection); dismiss()
                } catch { errorMessage = error.localizedDescription }
            }
        } message: { Text("Its emails, files, tasks and receipts will be kept.") }
        .task(id: snapshot) {
            scanning = true
            let results = await Task.detached(priority: .utility) {
                var values: [UUID: ReceiptSummary] = [:]
                for source in snapshot { guard !Task.isCancelled else { break }; values[source.id] = ReceiptDetector.detect(source) }
                return values
            }.value
            guard !Task.isCancelled else { return }; detected = results; scanning = false
        }
    }
    @ViewBuilder private var content: some View {
        switch tab {
        case .mail:
            ForEach(MailConversation.rows(mail, grouped: true)) { conversation in
                NavigationLink { GmailMessageView(message: conversation.latest) } label: {
                    CachedMessageRow(message: conversation.latest, messageCount: conversation.messages.count,
                        unread: !conversation.isRead, starred: conversation.isStarred)
                }
            }
            if mail.isEmpty { Text("Add a conversation to start this collection.").foregroundStyle(.secondary) }
        case .files:
            ForEach(files) { file in
                VStack(alignment: .leading, spacing: 8) {
                    AttachmentRow(attachment: file)
                    if let message = mail.first(where: { $0.id == file.messageID }) {
                        NavigationLink { GmailMessageView(message: message) } label: { Label(message.subject, systemImage: "envelope") }.font(.subheadline)
                    }
                }
            }
            if files.isEmpty { Text("No files in these downloaded conversations.").foregroundStyle(.secondary) }
        case .tasks:
            ForEach(tasks) { task in
                Button { editingTask = task } label: { Label(task.title, systemImage: task.isCompleted ? "checkmark.circle.fill" : "circle").foregroundStyle(.primary) }
            }
            if tasks.isEmpty { Text("Tasks linked to these conversations appear here.").foregroundStyle(.secondary) }
        case .receipts:
            if scanning { ProgressView("Finding receipts…") }
            ForEach(receipts) { receipt in
                if let message = mail.first(where: { $0.id == receipt.id }) {
                    NavigationLink { GmailMessageView(message: message) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.merchant).font(.headline)
                            Text(receipt.money?.display ?? "Amount not detected").font(.subheadline.monospacedDigit())
                            Text(receipt.reviewed ? "Reviewed" : "Detected · review in Receipts").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !scanning && receipts.isEmpty { Text("No receipts found in this collection.").foregroundStyle(.secondary) }
        }
    }
}

private struct CollectionMembershipView: View {
    let collectionID: UUID
    let accountID: UUID?
    @Query private var messages: [MailMessage]
    @Query private var metadata: [StoreMetadata]
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var errorMessage: String?
    private var collection: MailCollection? {
        metadata.first { $0.key == MailCollection.prefix + collectionID.uuidString }.flatMap { try? MailCollection.decode($0) }
    }
    var body: some View {
        let rows = MailConversation.rows(messages.filter { !$0.isDraft && !$0.isTrash && !$0.isSpam &&
            (accountID == nil || $0.accountID == accountID) }, grouped: true).filter { row in
                query.isEmpty || row.messages.contains { [$0.subject, $0.senderEmail, $0.senderName ?? ""].contains { $0.localizedCaseInsensitiveContains(query) } }
            }
        List {
            Text("Tap a conversation to add or remove it. Changes save immediately.").font(.caption).foregroundStyle(.secondary)
            ForEach(rows) { row in
                let included = collection?.links.contains { row.messages.contains(where: $0.contains) } == true
                Button {
                    do {
                        guard var collection, let repository = runtime.repository else { throw GmailError.reconnect }
                        if included { collection.links.removeAll { link in row.messages.contains(where: link.contains) } }
                        else { collection.links.append(MailCollectionLink(row.latest)) }
                        try repository.saveCollection(collection)
                    } catch { errorMessage = error.localizedDescription }
                } label: {
                    HStack {
                        Image(systemName: included ? "checkmark.circle.fill" : "circle").foregroundStyle(included ? MailStyle.accent : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.latest.subject.isEmpty ? "No subject" : row.latest.subject).font(.headline).foregroundStyle(.primary)
                            Text(row.latest.senderEmail).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5)
                }.accessibilityIdentifier("collectionMember-\(row.latest.remoteID)")
                    .accessibilityValue(included ? "Included" : "Not included")
            }
            if rows.isEmpty { ContentUnavailableView.search(text: query) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Conversations").searchable(text: $query, prompt: "Subject or sender")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
