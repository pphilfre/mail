import SwiftUI
import SwiftData

struct ComposeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRuntime.self) private var runtime
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @State private var draft: LocalDraft
    @State private var showAdditionalRecipients = false
    @State private var confirmingClose = false
    @State private var saveError: String?
    @State private var working = false
    @State private var sendUnconfirmed = false

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
                Text("Save draft keeps a copy on this device. Save to Gmail uploads it to Gmail. Sending requires a connected account. Messages and forwards currently contain text only; attachments are not included.")
            }
            Section {
                TextEditor(text: $draft.body)
                    .frame(minHeight: 260)
                    .accessibilityLabel("Message body")
                    .accessibilityIdentifier("composeBody")
            }
            if let saveError {
                Section { Text(saveError).foregroundStyle(.red) }
            }
            if !accounts.isEmpty {
                Section {
                    Button("Save to Gmail") { perform(send: false) }
                        .disabled(draft.accountID == nil || draft.isEmpty || working || sendUnconfirmed)
                    Button("Send", systemImage: "paperplane") { perform(send: true) }
                        .disabled(draft.accountID == nil || draft.to.isEmpty || working || sendUnconfirmed)
                    if working { ProgressView("Contacting Gmail…") }
                }
            }
        }
        .navigationTitle("New message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if draft.isEmpty { dismiss() } else { confirmingClose = true }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save draft", action: save)
                    .disabled(draft.isEmpty || working || sendUnconfirmed)
                    .accessibilityIdentifier("saveDraftButton")
            }
        }
        .interactiveDismissDisabled(!draft.isEmpty)
        .onAppear { if draft.accountID == nil && accounts.count == 1 { draft.accountID = accounts.first?.id } }
        .disabled(working)
        .confirmationDialog("Keep this draft?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Save draft", action: save)
            Button("Discard changes", role: .destructive) { dismiss() }
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
        draft.updatedAt = Date()
        do {
            try session.save(draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func perform(send: Bool) {
        guard !working, !sendUnconfirmed, let gmail = runtime.gmail else { return }
        draft.updatedAt = Date()
        do { try session.save(draft) } catch { saveError = error.localizedDescription; return }
        working = true; saveError = nil
        Task {
            defer { working = false }
            do {
                if send { try await gmail.send(draft) } else { try await gmail.saveRemoteDraft(draft) }
                try session.reloadDrafts(); dismiss()
            } catch {
                if error as? GmailError == .uncertainSend { sendUnconfirmed = true; try? session.reloadDrafts() }
                saveError = error.localizedDescription
            }
        }
    }
}
