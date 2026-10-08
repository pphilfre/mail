import SwiftUI
import SwiftData
import Translation

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
    @Query private var metadata: [StoreMetadata]
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
    @State private var showingActions = false
    @State private var pendingAction: MessageSheetAction?
    @State private var securityMessage: MailMessage?
    @State private var showingMove = false
    @State private var showingContact = false
    @State private var showingCalendar = false
    @State private var showingTranslation = false
    @State private var export: MessageExport?
    private var organisation: MailLocalOrganisation { MailLocalOrganisation.values(metadata)[MailLocalOrganisation.key(message)] ?? MailLocalOrganisation() }
    private var readerError: String? { localError ?? accounts.first(where: { $0.id == message.accountID })?.lastSyncError }
    private var thread: [MailMessage] { allMessages.isEmpty ? [message] : allMessages }
    private func bodyText(_ row: MailMessage) -> String {
        row.plainTextBody ?? row.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }.map(MailMIME.readableHTML) ?? row.snippet
    }
    private var conversationContent: some View {
      let files = Dictionary(grouping: attachments, by: \.messageID)
      return ScrollViewReader { proxy in
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
                ForEach(thread) { row in
                    ConversationMessageCard(message: row, initiallyExpanded: row.id == message.id,
                        attachments: files[row.id] ?? [], remoteImages: remoteImages || loadImagesOnce,
                        onReply: { reply(row, all: false) }, onReplyAll: { reply(row, all: true) }, onForward: { forward(row) },
                        onSender: { senderProfile = SenderProfileRequest(email: row.senderEmail, name: row.sender.displayName, accountID: row.accountID) },
                        account: accounts.first { $0.id == row.accountID }, onSecurity: { securityMessage = row }, onLoadImages: { loadImagesOnce = true })
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
            if thread.count > 3 { proxy.scrollTo(message.id, anchor: .top) }
            focusedMessage = true
        }
      }
    }
    private var readerChrome: some View {
        conversationContent
        .background(MailStyle.paper)
        .navigationTitle("Conversation").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") { feedback.select(); dismiss() }
                    .labelStyle(.iconOnly).accessibilityLabel("Back to inbox")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: MessageUtilities.readableCopy(message)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share message")
                if !message.isDraft {
                    Button("Forward", systemImage: "arrowshape.turn.up.right") { feedback.select(); forward(message) }.labelStyle(.iconOnly)
                    Button("Reply", systemImage: "arrowshape.turn.up.left") { feedback.select(); reply(message, all: false) }.labelStyle(.iconOnly)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        dockButton("Mark unread", "envelope.badge") { triage("unread") }
                        dockButton("Move", "folder") { showingMove = true }
                        dockButton("Delete", "trash", tint: .red) { triage("trash"); dismiss() }
                        dockButton("Archive", "archivebox") { triage("archive"); dismiss() }
                    }.padding(4).glassEffect(.regular.interactive(), in: .capsule)
                    Spacer(minLength: 0)
                    MailGlassButton(title: "More", symbol: "ellipsis") { showingActions = true }
                        .accessibilityIdentifier("readerMoreButton")
                }.padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: 600)
            }.frame(maxWidth: .infinity)
        }
        .task {
            await Task.yield()
            if !message.isRead { runtime.gmail?.action("read", message: message) }
            await refreshThread()
        }
    }
    private var readerWithActions: some View {
        readerChrome
        .sheet(item: $composing) { draft in NavigationStack { ComposeView(draft: draft) } }
        .sheet(isPresented: $showingActions, onDismiss: performPendingAction) {
            NavigationStack {
                MessageActionsSheet(message: message, folders: folders, organisation: organisation) {
                    pendingAction = $0; showingActions = false
                }
            }
        }
        .sheet(isPresented: $showingMove, onDismiss: performPendingAction) {
            NavigationStack {
                List {
                    Button("Inbox") { pendingAction = .triage("labelAdd:INBOX"); showingMove = false }
                    Button("Archive") { pendingAction = .triage("archive"); showingMove = false }
                    ForEach(folders.filter { $0.kindRaw == "user" }) { folder in
                        Button(folder.name) { pendingAction = .triage("move:" + folder.remoteID); showingMove = false }
                    }
                }.navigationTitle("Move message").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { showingMove = false } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $securityMessage) { row in NavigationStack { SecurityInspectorView(message: row, attachments: filesFor(row), imagesAllowed: remoteImages || loadImagesOnce) } }
        .sheet(isPresented: $showingContact) { SenderContactEditor(name: message.sender.displayName, email: message.senderEmail).ignoresSafeArea() }
    }
    var body: some View {
        readerWithActions
        .sheet(isPresented: $showingCalendar) { MessageCalendarEditor(subject: message.subject, notes: MessageUtilities.readableCopy(message)).ignoresSafeArea() }
        .sheet(item: $export, onDismiss: cleanExport) { MessageShareSheet(url: $0.url) }
        .translationPresentation(isPresented: $showingTranslation, text: bodyText(message))
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
        if let gmail = runtime.gmail { gmail.action(kind, message: message) }
        else {
            do { try runtime.repository?.enqueueBatch(kind, messages: [message]) }
            catch { localError = error.localizedDescription }
        }
    }
    private func filesFor(_ row: MailMessage) -> [MailAttachment] { attachments.filter { $0.messageID == row.id } }
    private func dockButton(_ title: String, _ symbol: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button { feedback.select(); action() } label: {
            Image(systemName: symbol).font(.system(size: 20)).frame(width: 48, height: 48)
        }.buttonStyle(.plain).foregroundStyle(tint).accessibilityLabel(title)
    }
    private func cleanExport() {
        // Share sheet owns the file until dismissal. Old temporary exports are pruned on the next export.
        export = nil
    }
    private func performPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        do {
            switch action {
            case .reply: reply(message, all: false)
            case .replyAll: reply(message, all: true)
            case .forward: forward(message)
            case .triage(let kind):
                triage(kind)
                if ["archive", "trash", "spam"].contains(kind) || kind.hasPrefix("move:") { dismiss() }
            case .sender: senderProfile = SenderProfileRequest(email: message.senderEmail, name: message.sender.displayName, accountID: message.accountID)
            case .contact: showingContact = true
            case .task: editingTask = try runtime.repository?.task(for: message)
            case .receipt:
                let source = ReceiptSource(message)
                let key = ReceiptOverride.prefix(message.accountID) + message.remoteID
                let value = try runtime.repository?.metadata(key).map(ReceiptOverride.decode)
                editingReceipt = ReceiptEditContext(source: source, detected: ReceiptDetector.detect(source), correction: value)
            case .collection: addingToCollection = true
            case .security: securityMessage = message
            case .translate: showingTranslation = true
            case .printMessage:
                if !MessageUtilities.printMessage(message) { localError = "The print sheet could not open. Try again." }
            case .savePDF: export = try MessageUtilities.pdf(message)
            case .calendar: showingCalendar = true
            case .forwardAttachment: forwardOriginal()
            case .pin(let pinned):
                try runtime.repository?.organise(message, pinned: pinned)
                feedback.show(pinned ? "Pinned on this device" : "Unpinned", symbol: "pin")
            case .snooze(let until):
                try runtime.repository?.organise(message, snoozedUntil: until)
                feedback.show("Snoozed on this device", detail: until.formatted(), symbol: "clock"); dismiss()
            case .unsnooze: try runtime.repository?.organise(message, clearSnooze: true)
            }
        } catch { localError = error.localizedDescription }
    }
    private func forwardOriginal() {
        guard let gmail = runtime.gmail else { localError = "Connect this Gmail account to download the original message."; return }
        preparingForward = true
        Task { @MainActor in
            defer { preparingForward = false }
            do {
                let data = try await gmail.originalMessage(message)
                var draft = LocalDraft(subject: "Fwd: " + message.subject, accountID: message.accountID)
                let file = try await runtime.draftAttachments.store(data, filename: "Forwarded message.eml", mimeType: "message/rfc822", draftID: draft.id, existing: [])
                draft.attachments = [file]; try session.save(draft); composing = draft
            } catch { localError = error.localizedDescription }
        }
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
