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
                recipientField("To", text: $draft.to).padding(.vertical, 14)
                Divider()
                if showAdditionalRecipients || !draft.cc.isEmpty || !draft.bcc.isEmpty {
                    recipientField("Cc", text: $draft.cc).padding(.vertical, 14)
                    Divider()
                    recipientField("Bcc", text: $draft.bcc).padding(.vertical, 14)
                    Divider()
                } else {
                    Button("Cc / Bcc", systemImage: "plus") { feedback.select(); showAdditionalRecipients = true }
                        .font(.subheadline).padding(.vertical, 14)
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
                TextField("Subject", text: $draft.subject)
                    .font(.title3.weight(.semibold)).padding(.vertical, 16)
                    .accessibilityIdentifier("composeSubject")
                    .onChange(of: draft.subject) { _, _ in draft.remoteThreadID = nil; draft.inReplyTo = nil; draft.referencesHeader = nil }
                Divider()
                if !RecipientInput.duplicateEmails([draft.to, draft.cc, draft.bcc]).isEmpty {
                    Text("Remove duplicate recipients: " + RecipientInput.duplicateEmails([draft.to, draft.cc, draft.bcc]).sorted().joined(separator: ", "))
                        .font(.caption).foregroundStyle(.red).padding(.vertical, 8)
                }
                TextEditor(text: $draft.body)
                    .font(.body).scrollContentBackground(.hidden)
                    .frame(minHeight: 300).padding(.top, 14)
                    .accessibilityLabel("Message body").accessibilityIdentifier("composeBody")
                ComposeAttachmentsView(draftID: draft.id, attachments: $draft.attachments, importing: $importingAttachments,
                    choosingFiles: $choosingFiles, photos: $photos) { attachmentError = $0 }
                    .padding(.vertical, 12)
                if let saveError { Text(saveError).font(.callout).foregroundStyle(.red).padding(.vertical, 8) }
                if let attachmentError { Text(attachmentError).font(.callout).foregroundStyle(.red).padding(.vertical, 8) }
                if working { ProgressView("Contacting Gmail…").padding(.vertical, 8) }
                if editor?.isSaved(draft) == true {
                    Text("Saved on this device").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("draftAutosaveStatus")
                } else if !draft.isEmpty {
                    Text(saveError == nil ? "Saving draft…" : "Draft couldn’t save").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.bottom, 16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
    }
    private var composeChrome: some View {
        composeFields
        .scrollDismissesKeyboard(.interactively)
        .background(MailStyle.paper)
        .safeAreaInset(edge: .bottom) { composerDock }
        .modifier(MailFeedbackOverlay(playsHaptics: false))
        .navigationTitle("New message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                MailCloseButton(title: "Close composer") {
                    if sendUnconfirmed { finished = true; dismiss() }
                    else if draft.isEmpty { discard() }
                    else { confirmingClose = true }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if accounts.isEmpty {
                    Button("Save draft", action: save)
                        .disabled(draft.isEmpty || working || sendUnconfirmed)
                        .accessibilityIdentifier("saveDraftButton")
                } else {
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
                        Button("Save draft", systemImage: "square.and.pencil", action: save).disabled(draft.isEmpty || sendUnconfirmed)
                        Button("Save to Gmail", systemImage: "icloud.and.arrow.up") { perform(send: false) }
                            .disabled(draft.accountID == nil || draft.isEmpty || recipientErrors || sendUnconfirmed || runtime.gmail == nil)
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
                                        draft.body += (draft.body.isEmpty ? "" : "\n\n") + item.body
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
                                if let appliedSignature, let body = MailSignature.replace(appliedSignature, with: item.body, in: draft.body) { draft.body = body }
                                else { draft.body = MailSignature.insert(item.body, in: draft.body) }
                                appliedSignature = item.body
                            }
                        }
                        Button("Manage signatures") { textLibrary = "Signatures"; showingTextLibrary = true }.disabled(sendingAccount == nil)
                        Button("Insert signature", systemImage: "signature", action: insertSignature).disabled(signatureForAccount().isEmpty)
                        Button("Edit account signature", systemImage: "pencil") { showingSignatureSettings = true }.disabled(sendingAccount == nil)
                    }
                    Section { Label("Scheduled sending · Coming soon", systemImage: "clock") }
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
        .sheet(isPresented: $showingTextLibrary) {
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
        .sheet(isPresented: $showingSignatureSettings) {
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
        .interactiveDismissDisabled(!draft.isEmpty || importingAttachments)
        .onAppear {
            if editor == nil {
                let saved = session.drafts.contains { $0.id == draft.id }
                manageSignature = !saved
                editor = DraftEditingSession(draft: draft, alreadySaved: saved)
                if let id = draft.accountID, !accounts.contains(where: { $0.id == id }) { draft.accountID = nil }
                if draft.accountID == nil {
                    draft.accountID = accounts.first { $0.id.uuidString == defaultAccount }?.id ?? (accounts.count == 1 ? accounts.first?.id : nil)
                }
                if !saved {
                    let signature = signatureForAccount()
                    draft.body = MailSignature.insert(signature, in: draft.body)
                    if !signature.isEmpty { appliedSignature = signature }
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
        .confirmationDialog("Keep this draft?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Save draft", action: save)
            Button("Discard changes", role: .destructive, action: discard)
            Button("Keep editing", role: .cancel) { }
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
        HStack(spacing: 6) {
            Button(action: insertSignature) {
                Image(systemName: "signature").frame(width: 48, height: 48).contentShape(.rect)
            }.disabled(signatureForAccount().isEmpty).accessibilityLabel("Signature")
            Menu {
                Button("Add bullet") { draft.body += "\n• " }
                Button("Add quote") { draft.body += "\n> " }
                Label("Rich text · Coming soon", systemImage: "textformat")
            } label: {
                Image(systemName: "textformat").frame(width: 48, height: 48).contentShape(.rect)
            }.accessibilityLabel("Text tools")
            if VNDocumentCameraViewController.isSupported {
                Button { feedback.select(); showingScanner = true } label: {
                    Image(systemName: "doc.viewfinder").frame(width: 48, height: 48).contentShape(.rect)
                }.accessibilityLabel("Scan document").disabled(draft.attachments.count >= DraftAttachmentStore.maximumCount)
            }
            PhotosPicker(selection: $photos, maxSelectionCount: max(1, DraftAttachmentStore.maximumCount - draft.attachments.count), matching: .images, preferredItemEncoding: .current) {
                Image(systemName: "photo").frame(width: 48, height: 48).contentShape(.rect)
            }.disabled(draft.attachments.count >= DraftAttachmentStore.maximumCount)
                .accessibilityLabel("Attach photo").accessibilityIdentifier("attachPhotoButton")
            Button { feedback.select(); choosingFiles = true } label: {
                Image(systemName: "paperclip").frame(width: 48, height: 48).contentShape(.rect)
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
        if !draft.body.hasSuffix(signature) { draft.body = MailSignature.insert(signature, in: draft.body) }
    }

    private func signatureForAccount() -> String {
        guard let id = draft.accountID else { return "" }
        let value = MailTextLibrary.read("Signatures", accountID: id).first?.body ?? ""
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
        do { try editor.checkpoint(draft, session: session); saveError = nil; return true }
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
        guard validRecipients, let repository = runtime.repository, let editor else { return }
        autosaveTask?.cancel()
        do {
            try editor.checkpoint(draft, session: session)
            try repository.schedule(draft, at: date)
            finished = true
            try? session.reloadDrafts()
            let id = draft.id
            feedback.show("Message queued", detail: date.timeIntervalSinceNow < 15 ? "Sending in 10 seconds" : date.formatted(),
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
