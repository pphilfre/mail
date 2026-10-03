import SwiftUI

struct ComposeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LocalDraft
    @State private var showAdditionalRecipients = false
    @State private var confirmingClose = false
    @State private var saveError: String?

    init(draft: LocalDraft = LocalDraft()) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("From", value: "No account connected")
                    .foregroundStyle(.secondary)
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
            } footer: {
                Text("You can save a draft on this device. Sending becomes available when an account is connected.")
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
                    .disabled(draft.isEmpty)
                    .accessibilityIdentifier("saveDraftButton")
            }
        }
        .interactiveDismissDisabled(!draft.isEmpty)
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
}
