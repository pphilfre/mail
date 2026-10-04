import SwiftUI
import SwiftData

struct ComposeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @State private var draft: LocalDraft
    @State private var showAdditionalRecipients = false
    @State private var confirmingClose = false
    @State private var saveError: String?
    @State private var working = false
    @State private var sendUnconfirmed = false
    @State private var editor: DraftEditingSession?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var finished = false

    init(draft: LocalDraft = LocalDraft()) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        Form {
            Section {
                if accounts.isEmpty {
                    LabeledContent("From", value: "No account connected").foregroundStyle(.secondary)
                } else {
                    Picker("From", selection: $draft.accountID) {
                        Text("Choose account").tag(UUID?.none)
                        ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
                    }.onChange(of: draft.accountID) { _, _ in
                        draft.remoteThreadID = nil; draft.inReplyTo = nil; draft.referencesHeader = nil
                    }
                }
                recipientField("To", text: $draft.to)
                    .accessibilityIdentifier("composeTo")
                if showAdditionalRecipients || !draft.cc.isEmpty || !draft.bcc.isEmpty {
                    recipientField("Cc", text: $draft.cc)
                    recipientField("Bcc", text: $draft.bcc)
                } else {
                    Button("Cc / Bcc") { showAdditionalRecipients = true }
                }
                TextField("Subject", text: $draft.subject)
                    .accessibilityIdentifier("composeSubject")
                    .onChange(of: draft.subject) { _, _ in draft.remoteThreadID = nil; draft.inReplyTo = nil; draft.referencesHeader = nil }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if editor?.isSaved(draft) == true {
                        Text("Saved on this device").accessibilityIdentifier("draftAutosaveStatus")
                    } else if !draft.isEmpty {
                        Text(saveError == nil ? "Saving draft…" : "Draft couldn’t save")
                    }
                    Text("Separate multiple addresses with commas.")
                }
            }
            Section {
                TextEditor(text: $draft.body)
                    .frame(minHeight: 260)
                    .accessibilityLabel("Message body")
                    .accessibilityIdentifier("composeBody")
            } footer: {
                Text("Messages contain text only. Attachments are not included.")
            }
            if let saveError {
                Section { Text(saveError).foregroundStyle(.red) }
            }
            if !accounts.isEmpty {
                Section {
                    Button("Save to Gmail") { perform(send: false) }
                        .disabled(draft.accountID == nil || draft.isEmpty || working || sendUnconfirmed)
                    if working { ProgressView("Contacting Gmail…") }
                }
            }
        }
        .navigationTitle("New message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
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
                    Button("Send", systemImage: "paperplane") { perform(send: true) }
                        .disabled(draft.accountID == nil || draft.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working || sendUnconfirmed)
                        .accessibilityIdentifier("sendButton")
                }
            }
        }
        .interactiveDismissDisabled(!draft.isEmpty)
        .onAppear {
            if editor == nil {
                editor = DraftEditingSession(draft: draft, alreadySaved: session.drafts.contains { $0.id == draft.id })
                if draft.accountID == nil && accounts.count == 1 { draft.accountID = accounts.first?.id }
                scheduleAutosave()
            }
        }
        .onChange(of: draft) { _, _ in scheduleAutosave() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { autosaveTask?.cancel(); checkpoint() }
        }
        .onDisappear { autosaveTask?.cancel(); checkpoint() }
        .disabled(working)
        .confirmationDialog("Keep this draft?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Save draft", action: save)
            Button("Discard changes", role: .destructive, action: discard)
            Button("Keep editing", role: .cancel) { }
        }
    }

    private func recipientField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
            TextField("Email addresses", text: text)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(title)
        }
    }

    private func save() {
        autosaveTask?.cancel()
        guard checkpoint() else { return }
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
        guard !working, !sendUnconfirmed, let gmail = runtime.gmail else { return }
        autosaveTask?.cancel()
        draft.updatedAt = Date()
        do { try session.save(draft) } catch { saveError = error.localizedDescription; return }
        working = true; saveError = nil
        Task {
            defer { working = false }
            do {
                if send { try await gmail.send(draft) } else { try await gmail.saveRemoteDraft(draft) }
                try session.reloadDrafts(); finished = true; dismiss()
            } catch {
                if error as? GmailError == .uncertainSend { sendUnconfirmed = true; try? session.reloadDrafts() }
                saveError = error.localizedDescription
            }
        }
    }
}
