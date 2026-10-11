import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

struct ComposeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRuntime.self) private var runtime
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var cachedMessages: [MailMessage]
    @AppStorage("defaultSendingAccount") private var defaultAccount = ""
    @State private var draft: LocalDraft
    @State private var showAdditionalRecipients = false
    @State private var confirmingClose = false
    @State private var saveError: String?
    @State private var working = false
    @State private var sendUnconfirmed = false
    @State private var editor: DraftEditingSession?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var finished = false
    @State private var suggestions: [RecipientSuggestion] = []
    @State private var appliedSignature: String?
    @State private var appliedSignatureID: UUID?
    @State private var signatureAccountID: UUID?
    @State private var manageSignature = false
    @State private var confirmingAttachment = false
    @State private var importingAttachments = false
    @State private var attachmentError: String?
    @State private var choosingFiles = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var showingSignatureSettings = false
    @State private var textLibrary: String?
    @State private var showingTextLibrary = false
    @State private var showingScanner = false
    @State private var showingSchedule = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var showingWriting = false
    @State private var writingSource = ""
    @State private var writingSnapshot = ""
    @State private var writingRange = NSRange(location: 0, length: 0)
    @State private var richEditor = RichMailEditorController()
    @State private var showingFormatting = false
    @State private var addingLink = false
    @State private var linkValue = ""
    @State private var openedSavedDraft = false
    private var hasCompositionContent: Bool {
        if openedSavedDraft || !draft.attachments.isEmpty || [draft.to, draft.cc, draft.bcc, draft.subject].contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return !draft.isEmpty }
        guard let appliedSignature, !appliedSignature.isEmpty else { return !draft.isEmpty }
        return draft.body != MailSignature.insert(appliedSignature, in: "")
    }
    private var sendingAccount: MailAccount? { accounts.first { $0.id == draft.accountID } }
    private var recipientErrors: Bool {
        [draft.to, draft.cc, draft.bcc].contains { !RecipientInput.invalid($0).isEmpty } ||
        !RecipientInput.duplicateEmails([draft.to, draft.cc, draft.bcc]).isEmpty
    }
    private var validRecipients: Bool { !RecipientInput.tokens(draft.to).isEmpty && !recipientErrors }

    init(draft: LocalDraft = LocalDraft()) {
        _draft = State(initialValue: draft)
    }

    private var composeFields: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    recipientField("To", text: $draft.to)
                    if !showAdditionalRecipients && draft.cc.isEmpty && draft.bcc.isEmpty {
                        Button("Cc / Bcc") { feedback.select(); showAdditionalRecipients = true }
                            .font(.caption).frame(minHeight: 44)
                    }
                }.padding(.vertical, 4)
                Divider()
                if showAdditionalRecipients || !draft.cc.isEmpty || !draft.bcc.isEmpty {
                    recipientField("Cc", text: $draft.cc).padding(.vertical, 4)
                    Divider()
                    recipientField("Bcc", text: $draft.bcc).padding(.vertical, 4)
                    Divider()
                }
                HStack(spacing: 8) {
                    Text("From").foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                    if accounts.isEmpty { Text("No account connected").foregroundStyle(.secondary) }
                    else {
                        Circle().fill(Color(mailHex: sendingAccount?.colourHex ?? "007AFF")).frame(width: 7, height: 7)
                        Picker("Sending account", selection: $draft.accountID) {
                            Text("Choose account").tag(UUID?.none)
                            ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
                        }.pickerStyle(.menu).labelsHidden().tint(.primary)
                            .accessibilityIdentifier("composeFromPicker")
                            .onChange(of: draft.accountID) { _, _ in
                                draft.remoteThreadID = nil; draft.inReplyTo = nil; draft.referencesHeader = nil
                                updateSignature(); prepareSuggestions()
                            }
                    }
                    Spacer(minLength: 0)
                }.font(.subheadline).padding(.vertical, 10)
                Divider()
                HStack(spacing: 8) {
                    Text("Subject").foregroundStyle(.secondary)
                    TextField("Subject", text: $draft.subject).font(.body.weight(.medium))
                    .accessibilityIdentifier("composeSubject")
                    .onChange(of: draft.subject) { _, _ in draft.remoteThreadID = nil; draft.inReplyTo = nil; draft.referencesHeader = nil }
                }.font(.subheadline).padding(.vertical, 12)
                Divider()
                if !RecipientInput.duplicateEmails([draft.to, draft.cc, draft.bcc]).isEmpty {
                    Text("Remove duplicate recipients: " + RecipientInput.duplicateEmails([draft.to, draft.cc, draft.bcc]).sorted().joined(separator: ", "))
                        .font(.caption).foregroundStyle(.red).padding(.vertical, 8)
                }
                RichMailEditor(text: $draft.body, document: $draft.richBody, controller: richEditor)
                    .frame(minHeight: 260)
                ComposeAttachmentsView(draftID: draft.id, attachments: $draft.attachments, importing: $importingAttachments,
                    choosingFiles: $choosingFiles, photos: $photos) { attachmentError = $0 }
                    .padding(.vertical, 12)
                if let saveError { Text(saveError).font(.callout).foregroundStyle(.red).padding(.vertical, 8) }
                if let attachmentError { Text(attachmentError).font(.callout).foregroundStyle(.red).padding(.vertical, 8) }
                if working { ProgressView("Contacting Gmail…").padding(.vertical, 8) }
                if hasCompositionContent && editor?.isSaved(draft) == true {
                    Text("Saved on this device").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("draftAutosaveStatus")
                } else if hasCompositionContent {
                    Text(saveError == nil ? "Saving draft…" : "Draft couldn’t save").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.bottom, 16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
    }
    private var composeChrome: some View {
        composeFields
        .scrollDismissesKeyboard(.interactively)
        .background(MailStyle.paper)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if showingFormatting { formattingBar }
                composerDock
            }
        }
        .modifier(MailFeedbackOverlay(playsHaptics: false))
        .navigationTitle("New message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    if sendUnconfirmed { finished = true; dismiss() }
                    else if !hasCompositionContent { discard() }
                    else { save() }
                }.accessibilityIdentifier("saveDraftButton").accessibilityHint("Saves your draft")
                    .disabled(working || importingAttachments)
            }
            ToolbarItem(placement: .confirmationAction) {
                if !accounts.isEmpty {
                    Button("Send", systemImage: "arrow.up") {
                        if draft.attachments.isEmpty && MailSignature.mentionsAttachment(draft.body) { confirmingAttachment = true }
                        else { perform(send: true) }
                    }
                        .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .disabled(draft.accountID == nil || !validRecipients || working || sendUnconfirmed)
                        .accessibilityIdentifier("sendButton")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Composer options", systemImage: "ellipsis") {
                    Section("Draft") {
                        Button("Save to Gmail", systemImage: "icloud.and.arrow.up") { perform(send: false) }
                            .disabled(draft.accountID == nil || draft.isEmpty || recipientErrors || sendUnconfirmed || runtime.gmail == nil)
                        Button("Discard changes", systemImage: "trash", role: .destructive) { confirmingClose = true }
                    }
                    Section("Sending account") {
                        Picker("From", selection: $draft.accountID) {
                            ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
                        }
                    }
                    Section("Reusable text") {
                        ForEach(["Templates", "Snippets"], id: \.self) { kind in
                            Menu(kind) {
                                ForEach(MailTextLibrary.read(kind)) { item in
                                    Button(item.name) {
                                        feedback.select()
                                        if kind == "Templates" && draft.subject.isEmpty { draft.subject = item.subject }
                                        draft.body = MailSignature.insertContent(item.body, in: draft.body)
                                    }
                                }
                                Button("Manage " + kind.lowercased()) { textLibrary = kind; showingTextLibrary = true }
                            }
                        }
                    }
                    Section("Signature") {
                        ForEach(MailTextLibrary.read("Signatures", accountID: draft.accountID)) { item in
                            Button(item.name) {
                                feedback.select()
                                chooseSignature(item.body, id: item.id)
                            }
                        }
                        Button("Manage signatures") { textLibrary = "Signatures"; showingTextLibrary = true }.disabled(sendingAccount == nil)
                        Button("Insert signature", systemImage: "signature", action: insertSignature).disabled(signatureForAccount().isEmpty)
                        Button("Edit account signature", systemImage: "pencil") { showingSignatureSettings = true }.disabled(sendingAccount == nil)
                    }
                    Button("Schedule send", systemImage: "clock") { showingSchedule = true }
                        .disabled(!validRecipients || draft.accountID == nil || runtime.gmail == nil)
                }.accessibilityIdentifier("composerOptionsButton")
            }
        }
        .sheet(isPresented: $showingScanner) {
            MailDocumentScanner { result in
                showingScanner = false
                switch result {
                case .failure(let error): attachmentError = error.localizedDescription
                case .success(let data):
                    importingAttachments = true
                    Task { @MainActor in
                        defer { importingAttachments = false }
                        do {
                            let item = try await runtime.draftAttachments.store(data, filename: "Scan.pdf", mimeType: "application/pdf", draftID: draft.id, existing: draft.attachments)
                            draft.attachments.append(item)
                        } catch { attachmentError = error.localizedDescription }
                    }
                }
            }
        }
        .sheet(isPresented: $showingTextLibrary, onDismiss: { if textLibrary == "Signatures" { updateSignature() } }) {
            NavigationStack {
                MailTextLibraryView(kind: textLibrary ?? "Snippets", accountID: textLibrary == "Signatures" ? draft.accountID : nil)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingTextLibrary = false } } }
            }
        }
        .sheet(isPresented: $showingSchedule) {
            NavigationStack {
                Form {
                    DatePicker("Send after", selection: $scheduledDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Text("Saved on this device. Dispatch sends when it is open and online after this time. Keep the app open for on-time delivery.").font(.footnote).foregroundStyle(.secondary)
                    if let saveError { Text(saveError).foregroundStyle(.red) }
                }.navigationTitle("Schedule send")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingSchedule = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Schedule") { queueSend(at: scheduledDate) } }
                    }
            }.presentationDetents([.medium])
        }
        .sheet(isPresented: $showingSignatureSettings, onDismiss: updateSignature) {
            if let sendingAccount {
                NavigationStack {
                    AccountPreferencesView(account: sendingAccount)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSignatureSettings = false } } }
                }
            }
        }
    }
    var body: some View {
        composeChrome
        .sheet(isPresented: $showingWriting) {
            NavigationStack {
                LocalWritingView(text: writingSource, tasks: [.polish, .shorten, .reply]) { suggestion in
                    guard draft.body == writingSnapshot else { saveError = "The draft changed while generating. Your current writing was kept."; return }
                    let next = (draft.body as NSString).replacingCharacters(in: writingRange, with: suggestion)
                    draft.richBody = draft.richBody?.replacingText(with: next)
                    draft.body = next
                }
            }
        }
        .interactiveDismissDisabled(importingAttachments || working || sendUnconfirmed || saveError != nil)
        .onAppear {
            if editor == nil {
                let saved = session.drafts.contains { $0.id == draft.id }
                openedSavedDraft = saved
                manageSignature = !saved
                editor = DraftEditingSession(draft: draft, alreadySaved: saved)
                if let id = draft.accountID, !accounts.contains(where: { $0.id == id }) { draft.accountID = nil }
                if draft.accountID == nil {
                    draft.accountID = accounts.first { $0.id.uuidString == defaultAccount }?.id ?? (accounts.count == 1 ? accounts.first?.id : nil)
                }
                if !saved {
                    let signature = signatureForAccount()
                    draft.body = MailSignature.insert(signature, in: draft.body)
                    if !signature.isEmpty {
                        appliedSignature = signature
                        appliedSignatureID = MailTextLibrary.read("Signatures", accountID: draft.accountID).first?.id
                        signatureAccountID = draft.accountID
                    }
                } else {
                    let candidates = MailTextLibrary.read("Signatures", accountID: draft.accountID).sorted { $0.body.count > $1.body.count }
                    if let match = candidates.first(where: { MailSignature.replace($0.body, with: $0.body, in: draft.body) != nil }) {
                        appliedSignature = match.body; appliedSignatureID = match.id
                        signatureAccountID = draft.accountID; manageSignature = true
                    }
                }
                prepareSuggestions()
                scheduleAutosave()
            }
        }
        .onChange(of: draft) { _, _ in scheduleAutosave() }
        .onChange(of: importingAttachments) { _, value in
            if value { attachmentError = nil } else { checkpoint() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { autosaveTask?.cancel(); checkpoint() }
        }
        .onDisappear { autosaveTask?.cancel(); checkpoint() }
        .disabled(working || importingAttachments)
        .confirmationDialog("Discard your changes?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive, action: discard)
            Button("Keep editing", role: .cancel) { }
        } message: { Text("An existing draft returns to the version you opened. A new draft is deleted.") }
        .alert("Add link", isPresented: $addingLink) {
            TextField("https://example.com", text: $linkValue).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Add") { richEditor.link(linkValue) }.disabled(!RichMailBody.safeLink(linkValue))
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Your message mentions an attachment", isPresented: $confirmingAttachment, titleVisibility: .visible) {
            Button("Send without attachments") { perform(send: true) }
            Button("Keep editing", role: .cancel) { }
        } message: { Text("No files are attached. Keep editing to add one, or send this message as it is.") }
    }

    private func recipientField(_ title: String, text: Binding<String>) -> some View {
        RecipientField(title: title, text: text, suggestions: suggestions,
            excluded: Set([draft.to, draft.cc, draft.bcc].flatMap(RecipientInput.tokens).compactMap { RecipientInput.address($0)?.email.lowercased() }))
    }
    private var composerDock: some View {
        HStack(spacing: 0) {
            Button {
                feedback.select()
                writingSnapshot = draft.body
                if let view = richEditor.view, view.text == draft.body, view.selectedRange.length > 0 {
                    let selection = view.selectedRange
                    writingRange = selection
                } else { writingRange = NSRange(MailSignature.authoredRange(in: draft.body), in: draft.body) }
                writingSource = (draft.body as NSString).substring(with: writingRange)
                showingWriting = true
            } label: {
                Image(systemName: "sparkles").foregroundStyle(MailIntelligenceStyle.gradient).frame(width: 44, height: 44)
            }.accessibilityLabel("Polish writing").accessibilityIdentifier("polishWritingButton").disabled(draft.body.isEmpty)
            Button { showingFormatting.toggle() } label: {
                Image(systemName: "textformat").frame(width: 44, height: 44).contentShape(.rect)
            }.foregroundStyle(showingFormatting ? MailStyle.accent : .primary).accessibilityLabel("Formatting")
                .accessibilityAddTraits(showingFormatting ? .isSelected : [])
            if VNDocumentCameraViewController.isSupported {
                Button { feedback.select(); showingScanner = true } label: {
                    Image(systemName: "doc.viewfinder").frame(width: 44, height: 44).contentShape(.rect)
                }.accessibilityLabel("Scan document").disabled(draft.attachments.count >= DraftAttachmentStore.maximumCount)
            }
            PhotosPicker(selection: $photos, maxSelectionCount: max(1, DraftAttachmentStore.maximumCount - draft.attachments.count), matching: .images, preferredItemEncoding: .current) {
                Image(systemName: "photo").frame(width: 44, height: 44).contentShape(.rect)
            }.disabled(draft.attachments.count >= DraftAttachmentStore.maximumCount)
                .accessibilityLabel("Attach photo").accessibilityIdentifier("attachPhotoButton")
            Button { feedback.select(); choosingFiles = true } label: {
                Image(systemName: "paperclip").frame(width: 44, height: 44).contentShape(.rect)
            }.accessibilityLabel("Attach file").disabled(draft.attachments.count >= DraftAttachmentStore.maximumCount)
                .accessibilityIdentifier("attachFileButton")
        }
        .buttonStyle(.plain).font(.system(size: 21)).frame(height: 52)
        .padding(.horizontal, 14)
        .environment(\.defaultMinListRowHeight, 44)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(importingAttachments || working || sendUnconfirmed)
        .padding(.vertical, 10).frame(maxWidth: .infinity)
    }
    private func insertSignature() {
        let signature = signatureForAccount()
        guard !signature.isEmpty else { return }
        feedback.select()
        chooseSignature(signature)
    }
    private var formattingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                formatButton("Bold", "bold", selected: richEditor.bold) { richEditor.toggleTrait(.traitBold) }
                formatButton("Italic", "italic", selected: richEditor.italic) { richEditor.toggleTrait(.traitItalic) }
                formatButton("Underline", "underline", selected: richEditor.underline) { richEditor.toggle(.underlineStyle) }
                formatButton("Strikethrough", "strikethrough") { richEditor.toggle(.strikethroughStyle) }
                formatButton("Bulleted list", "list.bullet") { richEditor.list(numbered: false) }
                formatButton("Numbered list", "list.number") { richEditor.list(numbered: true) }
                formatButton("Add link", "link") { linkValue = ""; addingLink = true }
                formatButton("Quote", "text.quote") { richEditor.quote() }
            }.padding(.horizontal, 12)
        }.background(.regularMaterial)
    }
    private func formatButton(_ title: String, _ symbol: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
            .buttonStyle(.plain).foregroundStyle(selected ? MailStyle.accent : .primary)
            .background(selected ? MailStyle.accent.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
            .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func chooseSignature(_ signature: String, id: UUID? = nil) {
        let known = accounts.flatMap { MailTextLibrary.read("Signatures", accountID: $0.id).map(\.body) }
        draft.body = MailSignature.choose(signature, replacing: known + [appliedSignature].compactMap { $0 }, in: draft.body)
        appliedSignature = signature
        appliedSignatureID = id ?? MailTextLibrary.read("Signatures", accountID: draft.accountID).first { $0.body == signature }?.id
        signatureAccountID = draft.accountID
        manageSignature = true
    }

    private func signatureForAccount() -> String {
        guard let id = draft.accountID else { return "" }
        let items = MailTextLibrary.read("Signatures", accountID: id)
        let value = (signatureAccountID == id ? items.first { $0.id == appliedSignatureID } : nil)?.body ?? items.first?.body ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : value
    }
    private func updateSignature() {
        guard editor != nil, manageSignature else { return }
        let next = signatureForAccount()
        if let previous = appliedSignature {
            guard let body = MailSignature.replace(previous, with: next, in: draft.body) else { appliedSignature = nil; manageSignature = false; return }
            draft.body = body
        } else {
            draft.body = MailSignature.insert(next, in: draft.body)
        }
        appliedSignature = next.isEmpty ? nil : next
        appliedSignatureID = MailTextLibrary.read("Signatures", accountID: draft.accountID).first { $0.body == next }?.id
        signatureAccountID = draft.accountID
    }
    private func prepareSuggestions() {
        let own = Set(accounts.map { $0.email.lowercased() })
        var candidates: [String: RecipientSuggestion] = [:]
        for message in cachedMessages where !message.isSpam && !message.isTrash && (draft.accountID == nil || message.accountID == draft.accountID) {
            for address in [message.sender] + message.to + message.cc {
                let key = address.email.lowercased()
                guard MailMIME.valid(address.email), !own.contains(key) else { continue }
                let existing = candidates[key]
                candidates[key] = RecipientSuggestion(address: existing?.address ?? address, frequency: (existing?.frequency ?? 0) + 1,
                    latest: max(existing?.latest ?? .distantPast, message.receivedAt))
            }
        }
        suggestions = candidates.values.sorted {
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            if $0.latest != $1.latest { return $0.latest > $1.latest }
            return $0.id < $1.id
        }
    }

    private func save() {
        autosaveTask?.cancel()
        guard checkpoint() else { return }
        feedback.show("Draft saved", detail: "Ready when you are", symbol: "square.and.pencil")
        finished = true; dismiss()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard !working, !sendUnconfirmed, !finished else { return }
        autosaveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(600)) }
            catch { return }
            guard !Task.isCancelled else { return }
            checkpoint()
        }
    }

    @discardableResult private func checkpoint() -> Bool {
        guard !working, !sendUnconfirmed, !finished, let editor else { return false }
        if let rich = draft.richBody, rich.text != draft.body { draft.richBody = rich.replacingText(with: draft.body) }
        var snapshot = draft
        if !hasCompositionContent { snapshot.body = ""; snapshot.richBody = nil }
        do { try editor.checkpoint(snapshot, session: session); saveError = nil; return true }
        catch { saveError = error.localizedDescription; return false }
    }

    private func discard() {
        autosaveTask?.cancel()
        guard !working, !sendUnconfirmed else { return }
        do {
            try editor?.discard(session: session)
            finished = true; dismiss()
        } catch { saveError = error.localizedDescription }
    }

    private func queueSend(at date: Date) {
        guard validRecipients, let repository = runtime.repository else { return }
        autosaveTask?.cancel()
        guard checkpoint() else { return }
        do {
            try repository.schedule(draft, at: date)
            finished = true
            try? session.reloadDrafts()
            let id = draft.id
            feedback.show("Message queued", detail: date.timeIntervalSinceNow < 15 ? "Undo available for 10 seconds" : date.formatted(),
                          symbol: "clock", expiresAt: date, undo: {
                do { try repository.cancelScheduled(id); try session.reloadDrafts(); feedback.show("Send cancelled", detail: "Your message is in Drafts") }
                catch { feedback.show("Couldn’t cancel send", detail: error.localizedDescription, tone: .error) }
            })
            showingSchedule = false
            dismiss()
        } catch { saveError = error.localizedDescription }
    }

    private func perform(send: Bool) {
        guard !working, !sendUnconfirmed, let gmail = runtime.gmail, let editor else { return }
        if recipientErrors || (send && !validRecipients) { saveError = "Check the recipients before contacting Gmail."; return }
        if send { queueSend(at: Date().addingTimeInterval(10)); return }
        autosaveTask?.cancel()
        do { try editor.checkpoint(draft, session: session) } catch { saveError = error.localizedDescription; return }
        working = true; saveError = nil
        Task {
            defer { working = false }
            do {
                try await gmail.saveRemoteDraft(draft)
                // Provider success is authoritative even if refreshing the local draft list fails.
                finished = true
                do { try session.reloadDrafts() }
                catch { session.storageError = error.localizedDescription }
                feedback.show("Draft saved to Gmail", symbol: "checkmark")
                dismiss()
            } catch {
                if error as? GmailError == .uncertainSend { sendUnconfirmed = true; try? session.reloadDrafts() }
                saveError = error.localizedDescription
                feedback.show(sendUnconfirmed ? "Check your Outbox" : "Couldn’t complete that", detail: saveError,
                              symbol: "exclamationmark", tone: sendUnconfirmed ? .information : .error)
            }
        }
    }
}
