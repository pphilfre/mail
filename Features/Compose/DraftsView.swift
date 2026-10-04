import SwiftUI
import SwiftData

struct DraftsView: View {
    var accountID: UUID? = nil
    var body: some View {
        List { DraftSections(accountID: accountID) }
            .listStyle(.plain).scrollContentBackground(.hidden).background(MailStyle.paper)
            .navigationTitle("Drafts")
    }
}

/// Shared by the Drafts mailbox and the inbox shortcut; local copies remain editable offline.
struct DraftSections: View {
    var accountID: UUID? = nil
    @Environment(AppSession.self) private var session
    @Environment(AppRuntime.self) private var runtime
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    @Query private var outgoing: [OutgoingMessage]
    @Query private var links: [StoreMetadata]
    @State private var editingDraft: LocalDraft?
    @State private var errorMessage: String?
    @State private var deletingDraft: LocalDraft?
    @State private var refreshing = false
    private var local: [LocalDraft] { session.drafts.filter { accountID == nil || $0.accountID == accountID } }
    private var remote: [MailMessage] {
        let hidden = DraftLinks.hiddenMessageIDs(outgoing: outgoing, links: links, accountID: accountID)
        return messages.filter { $0.isDraft && !$0.isTrash && (accountID == nil || $0.accountID == accountID) && !hidden.contains($0.identity) }
    }
    private func accountName(_ id: UUID?) -> String { accounts.first(where: { $0.id == id })?.email ?? "No account selected" }
    private func hasGmailCopy(_ draft: LocalDraft) -> Bool {
        guard let row = outgoing.first(where: { $0.id == draft.id }), let accountID = row.accountID, let remoteID = row.remoteDraftID else { return false }
        return links.contains { $0.key == DraftLinks.key(accountID, remoteID) }
    }

    var body: some View {
        Group {
            if !local.isEmpty {
              Section {
                ForEach(local) { draft in
                Button {
                    editingDraft = draft
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.displaySubject).font(.headline).foregroundStyle(.primary)
                        Text(draft.to.isEmpty ? "No recipients" : draft.to)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Text(draft.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text(accountName(draft.accountID)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack {
                            Text(hasGmailCopy(draft) ? "Local edits · Gmail copy" : "On this device")
                            Spacer()
                            Text(draft.updatedAt, format: .dateTime.month().day().hour().minute())
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("localDraft-\(draft.id.uuidString)")
                .swipeActions {
                    Button("Delete local copy", role: .destructive) { deletingDraft = draft }
                }
                }
              } header: {
                Text("On this device")
              } footer: {
                Text("Edits are saved on this device. Use Save to Gmail in the composer to update the Gmail copy.")
              }
            }
            if !remote.isEmpty {
                Section("In Gmail") {
                    ForEach(remote) { message in
                        NavigationLink { GmailMessageView(message: message) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.subject.isEmpty ? "No subject" : message.subject).font(.headline).foregroundStyle(.primary)
                                Text(message.to.map(\.email).joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Text(message.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                Text(accountName(message.accountID)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            if local.isEmpty && remote.isEmpty {
                ContentUnavailableView("No drafts", systemImage: "doc", description: Text("Saved drafts will appear here."))
            }
            if refreshing { ProgressView("Updating Gmail drafts…") }
            ForEach(accounts.filter { (accountID == nil || $0.id == accountID) && runtime.gmail?.hasOlder($0.id, mailbox: "Drafts") == true }) { account in
                Button("Load older drafts · \(account.email)") {
                    Task { await runtime.gmail?.loadOlder(account.id, mailbox: "Drafts") }
                }.disabled(runtime.gmail?.syncing.contains(account.id) == true)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await refresh() } }.disabled(refreshing)
                }
            }
        }
        .sheet(item: $editingDraft) { draft in
            NavigationStack { ComposeView(draft: draft) }
        }
        .confirmationDialog("Delete the local copy?", isPresented: Binding(
            get: { deletingDraft != nil }, set: { if !$0 { deletingDraft = nil } }
        )) {
            Button("Delete local copy", role: .destructive) {
                if let draft = deletingDraft {
                    do { try session.deleteDraft(id: draft.id) }
                    catch { errorMessage = error.localizedDescription }
                }
                deletingDraft = nil
            }
        } message: { Text("Any copy saved in Gmail will remain there.") }
        .task(id: accountID) { await refresh() }
    }
    private func refresh() async {
        guard !refreshing, let gmail = runtime.gmail else { return }
        refreshing = true; errorMessage = nil
        defer { refreshing = false }
        do {
            try session.reloadDrafts()
            await gmail.loadMailbox("Drafts", accountID: accountID)
            try await gmail.refreshDraftLinks(accountID: accountID)
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
}
