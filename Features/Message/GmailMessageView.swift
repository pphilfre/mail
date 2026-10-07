import SwiftUI
import SwiftData

struct GmailMessageView: View {
    let message: MailMessage
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppSession.self) private var session
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MailMessage.receivedAt) private var allMessages: [MailMessage]
    @Query private var attachments: [MailAttachment]
    @Query private var accounts: [MailAccount]
    @Query(sort: \MailFolder.name) private var folders: [MailFolder]
    init(message: MailMessage) {
        self.message = message
        let accountID = message.accountID
        let threadID = message.remoteThreadID
        let remoteID = message.remoteID
        let hasThread = !threadID.isEmpty
        if hasThread {
            _allMessages = Query(filter: #Predicate<MailMessage> { $0.accountID == accountID && $0.remoteThreadID == threadID }, sort: \MailMessage.receivedAt)
        } else {
            _allMessages = Query(filter: #Predicate<MailMessage> { $0.accountID == accountID && $0.remoteID == remoteID }, sort: \MailMessage.receivedAt)
        }
        _attachments = Query(filter: #Predicate<MailAttachment> { $0.accountID == accountID })
        _folders = Query(filter: #Predicate<MailFolder> { $0.accountID == accountID }, sort: \MailFolder.name)
    }
    @AppStorage("remoteImages") private var remoteImages = false
    @State private var loadImagesOnce = false
    @State private var composing: LocalDraft?
    @State private var localError: String?
    @State private var confirmingDraftDeletion = false
    @State private var loadingThread = false
    @State private var focusedMessage = false
    @State private var forwardingMessage: MailMessage?
    @State private var preparingForward = false
    @State private var editingTask: MailTask?
    @State private var editingReceipt: ReceiptEditContext?
    @State private var senderProfile: SenderProfileRequest?
    @State private var addingToCollection = false
    private var readerError: String? { localError ?? accounts.first(where: { $0.id == message.accountID })?.lastSyncError }
    private var thread: [MailMessage] { allMessages.isEmpty ? [message] : allMessages }
    private func bodyText(_ row: MailMessage) -> String {
        row.plainTextBody ?? row.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }.map(MailMIME.readableHTML) ?? row.snippet
    }
    var body: some View {
      let files = Dictionary(grouping: attachments, by: \.messageID)
      ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(message.subject.isEmpty ? "No subject" : message.subject)
                    .font(.largeTitle.weight(.bold)).tracking(-0.8).textSelection(.enabled)
                    .padding(.horizontal, 4).padding(.vertical, 8)
                if preparingForward { ProgressView("Preparing attachments…").font(.caption) }
                if let error = readerError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                        Button("Retry") { Task { await refreshThread(syncFirst: true) } }.disabled(loadingThread)
                    }
                }
                if !remoteImages && !loadImagesOnce && thread.contains(where: { row in
                    row.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }.map(MailMIME.hasRemoteImages) == true
                }) {
                    HStack {
                        Label("Remote images are off", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Load images") { feedback.select(); loadImagesOnce = true }.font(.caption.bold())
                    }.padding(14).background(MailStyle.paper, in: .rect(cornerRadius: 16))
                }
                ForEach(thread) { row in
                    ConversationMessageCard(message: row, initiallyExpanded: row.id == message.id,
                        attachments: files[row.id] ?? [], remoteImages: remoteImages || loadImagesOnce,
                        onReply: { reply(row, all: false) }, onReplyAll: { reply(row, all: true) }, onForward: { forward(row) },
                        onSender: { senderProfile = SenderProfileRequest(email: row.senderEmail, name: row.sender.displayName, accountID: row.accountID) })
                        .id(row.id)
                }
                if message.isDraft {
                    Button("Edit Gmail draft") {
                        Task {
                            do {
                                guard let gmail = runtime.gmail else { return }
                                composing = try await gmail.importDraft(message)
                                try session.reloadDrafts()
                            } catch { localError = error.localizedDescription }
                        }
                    }
                    Button("Delete Gmail draft", role: .destructive) {
                        confirmingDraftDeletion = true
                    }
                }
            }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .task(id: thread.map(\.id)) {
            guard !focusedMessage, thread.contains(where: { $0.id == message.id }) else { return }
            await Task.yield()
            proxy.scrollTo(message.id, anchor: .top)
            focusedMessage = true
        }
      }
        .background(MailStyle.canvas)
        .navigationTitle("Conversation").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(message.isStarred ? "Unstar" : "Star", systemImage: message.isStarred ? "star.fill" : "star") {
                    triage(message.isStarred ? "unstar" : "star")
                }
                Menu("More", systemImage: "ellipsis.circle") {
                    if !message.isDraft {
                        Button("Add to collection", systemImage: "folder.badge.plus") { addingToCollection = true }
                            .accessibilityIdentifier("addToCollectionButton")
                        Button("Make task", systemImage: "checklist") {
                            do { editingTask = try runtime.repository?.task(for: message) }
                            catch { localError = error.localizedDescription }
                        }.accessibilityIdentifier("makeMailTaskButton")
                        Button("Save receipt", systemImage: "receipt") {
                            do {
                                let source = ReceiptSource(message)
                                let key = ReceiptOverride.prefix(message.accountID) + message.remoteID
                                let value = try runtime.repository?.metadata(key).map(ReceiptOverride.decode)
                                editingReceipt = ReceiptEditContext(source: source, detected: ReceiptDetector.detect(source), correction: value)
                            } catch { localError = error.localizedDescription }
                        }.accessibilityIdentifier("makeReceiptButton")
                        Divider()
                    }
                    Button(message.isRead ? "Mark unread" : "Mark read", systemImage: message.isRead ? "envelope.badge" : "envelope.open") { triage(message.isRead ? "unread" : "read") }
                        .accessibilityIdentifier("readerReadButton")
                    Button("Archive", systemImage: "archivebox") { triage("archive"); dismiss() }
                    Button(message.isSpam ? "Not spam" : "Move to Spam", systemImage: "exclamationmark.shield") {
                        triage(message.isSpam ? "notSpam" : "spam"); dismiss()
                    }
                    Button(message.isTrash ? "Restore" : "Move to Trash", systemImage: "trash") {
                        triage(message.isTrash ? "restore" : "trash"); dismiss()
                    }
                    Menu("Labels") {
                        ForEach(folders.filter { $0.accountID == message.accountID && $0.kindRaw == "user" }) { folder in
                            Button {
                                triage((message.folderIDs.contains(folder.remoteID) ? "labelRemove:" : "labelAdd:") + folder.remoteID)
                            } label: {
                                Label(folder.name, systemImage: message.folderIDs.contains(folder.remoteID) ? "checkmark" : "tag")
                            }
                        }
                    }
                }
            }
        }
        .task {
            await Task.yield()
            if !message.isRead { runtime.gmail?.action("read", message: message) }
            await refreshThread()
        }
        .sheet(item: $composing) { draft in NavigationStack { ComposeView(draft: draft) } }
        .sheet(item: $editingTask) { task in NavigationStack { MailTaskEditor(task: task) } }
        .sheet(item: $editingReceipt) { context in NavigationStack { ReceiptEditor(context: context) } }
        .sheet(isPresented: $addingToCollection) { NavigationStack { AddToCollectionView(message: message) } }
        .sheet(item: $senderProfile) { person in
            NavigationStack {
                SenderProfileView(email: person.email, name: person.name, initialAccountID: person.accountID)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { senderProfile = nil } } }
            }
        }
        .disabled(preparingForward)
        .confirmationDialog("Include attachments?", isPresented: Binding(
            get: { forwardingMessage != nil }, set: { if !$0 { forwardingMessage = nil } }
        ), titleVisibility: .visible) {
            if let row = forwardingMessage {
                Button("Forward with attachments") { prepareForward(row) }
                Button("Forward text only") { composing = forwardDraft(row) }
            }
            Button("Cancel", role: .cancel) { forwardingMessage = nil }
        } message: { Text("Attached files will be downloaded and copied into your new draft.") }
        .confirmationDialog("Delete this Gmail draft?", isPresented: $confirmingDraftDeletion, titleVisibility: .visible) {
            Button("Delete draft", role: .destructive) {
                Task {
                    do {
                        guard let gmail = runtime.gmail else { return }
                        try await gmail.deleteRemoteDraft(message)
                        try session.reloadDrafts(); dismiss()
                    } catch { localError = error.localizedDescription }
                }
            }
        }
    }
    private func triage(_ kind: String) {
        feedback.triageKind = kind
        runtime.gmail?.action(kind, message: message)
    }
    private func refreshThread(syncFirst: Bool = false) async {
        guard !loadingThread, let gmail = runtime.gmail else { return }
        loadingThread = true; localError = nil
        defer { loadingThread = false }
        if syncFirst { await gmail.sync(message.accountID) }
        do { try await gmail.loadThread(message, force: syncFirst) }
        catch { if !Task.isCancelled { localError = error.localizedDescription } }
    }
    private func reply(_ row: MailMessage, all: Bool) {
        let own = accounts.first { $0.id == row.accountID }?.email.lowercased() ?? ""
        let recipients = MailReplyRecipients.make(sender: row.sender, replyTo: row.replyTo, to: row.to, cc: row.cc,
            ownEmail: own, replyAll: all)
        let references = [row.referencesHeader, row.internetMessageID].compactMap { $0 }.joined(separator: " ")
        composing = LocalDraft(to: recipients.to.joined(separator: ", "), cc: recipients.cc.joined(separator: ", "), subject: row.subject,
            body: "\n\nOn \(row.receivedAt.formatted()), \(row.sender.displayName) wrote:\n" + bodyText(row).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n"),
            accountID: row.accountID, remoteThreadID: row.internetMessageID == nil ? nil : row.remoteThreadID,
            inReplyTo: row.internetMessageID, referencesHeader: references.isEmpty ? nil : references)
    }
    private func forward(_ row: MailMessage) {
        guard !preparingForward else { return }
        if attachments.contains(where: { $0.messageID == row.id }) { forwardingMessage = row }
        else { composing = forwardDraft(row) }
    }
    private func forwardDraft(_ row: MailMessage) -> LocalDraft {
        LocalDraft(subject: "Fwd: " + row.subject,
            body: "\n\nForwarded message\nFrom: \(row.senderEmail)\nDate: \(row.receivedAt.formatted())\nSubject: \(row.subject)\n\n" + bodyText(row), accountID: row.accountID)
    }
    private func prepareForward(_ row: MailMessage) {
        guard let gmail = runtime.gmail else { return }
        let files = attachments.filter { $0.messageID == row.id }
        preparingForward = true; localError = nil
        Task { @MainActor in
            defer { preparingForward = false }
            do {
                guard files.count <= DraftAttachmentStore.maximumCount else { throw ComposeAttachmentError.tooMany }
                var total = 0
                for file in files {
                    guard file.byteCount >= 0, file.byteCount <= DraftAttachmentStore.maximumBytes - total else { throw ComposeAttachmentError.tooLarge }
                    total += file.byteCount
                }
                var draft = forwardDraft(row)
                for file in files {
                    let url = try await gmail.download(file)
                    let item = try await runtime.draftAttachments.importFile(url, draftID: draft.id, existing: draft.attachments)
                    draft.attachments.append(item)
                }
                // Open only when every selected file is preserved; failure never sends a partial copy.
                try session.save(draft)
                composing = draft
            } catch { localError = error.localizedDescription }
        }
    }
}
