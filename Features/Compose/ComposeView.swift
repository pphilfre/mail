import SwiftUI
import SwiftData
import PhotosUI

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
                    Section("Signature") {
                        Button("Insert signature", systemImage: "signature", action: insertSignature).disabled(signatureForAccount().isEmpty)
                        Button("Edit account signature", systemImage: "pencil") { showingSignatureSettings = true }.disabled(sendingAccount == nil)
                    }
                    Section { Label("Scheduled sending · Coming soon", systemImage: "clock") }
                }.accessibilityIdentifier("composerOptionsButton")
            }
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
            Button("Signature", systemImage: "signature", action: insertSignature)
                .disabled(signatureForAccount().isEmpty).labelStyle(.iconOnly).frame(width: 48, height: 48)
            Menu("Text tools", systemImage: "textformat") {
                Button("Add bullet") { draft.body += "\n• " }
                Button("Add quote") { draft.body += "\n> " }
                Label("Rich text · Coming soon", systemImage: "textformat")
            }.labelStyle(.iconOnly).frame(width: 48, height: 48)
            PhotosPicker(selection: $photos, maxSelectionCount: max(1, DraftAttachmentStore.maximumCount - draft.attachments.count), matching: .images, preferredItemEncoding: .current) {
                Image(systemName: "photo")
            }.frame(width: 48, height: 48).disabled(draft.attachments.count >= DraftAttachmentStore.maximumCount)
                .accessibilityLabel("Attach photo").accessibilityIdentifier("attachPhotoButton")
            Button("Attach file", systemImage: "paperclip") { feedback.select(); choosingFiles = true }
                .labelStyle(.iconOnly).frame(width: 48, height: 48).disabled(draft.attachments.count >= DraftAttachmentStore.maximumCount)
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
        let value = UserDefaults.standard.string(forKey: MailSignature.key(id)) ?? ""
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

    private func perform(send: Bool) {
        guard !working, !sendUnconfirmed, let gmail = runtime.gmail, let editor else { return }
        if recipientErrors || (send && !validRecipients) { saveError = "Check the recipients before contacting Gmail."; return }
        autosaveTask?.cancel()
        do { try editor.checkpoint(draft, session: session) } catch { saveError = error.localizedDescription; return }
        working = true; saveError = nil
        Task {
            defer { working = false }
            do {
                if send { try await gmail.send(draft) } else { try await gmail.saveRemoteDraft(draft) }
                // Provider success is authoritative even if refreshing the local draft list fails.
                finished = true
                do { try session.reloadDrafts() }
                catch { session.storageError = error.localizedDescription }
                feedback.show(send ? "Message sent" : "Draft saved to Gmail", detail: send ? "On its way" : nil,
                              symbol: send ? "paperplane.fill" : "checkmark")
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
