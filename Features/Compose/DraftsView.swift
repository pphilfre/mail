import SwiftUI
import SwiftData

enum DraftLocation: String, CaseIterable, Identifiable {
    case device = "On this device", gmail = "In Gmail"
    var id: String { rawValue }
}

struct DraftsView: View {
    var accountID: UUID? = nil
    @State private var editingDraft: LocalDraft?
    @State private var location = DraftLocation.device
    var body: some View {
        List { DraftSections(accountID: accountID, location: location, onEdit: { editingDraft = $0 }) }
            .listStyle(.plain).scrollContentBackground(.hidden).background(MailStyle.paper)
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) {
                HStack(spacing: 8) { MailNavigationTitle(title: "Drafts"); DraftLocationPicker(selection: $location) }
            } }
            .sheet(item: $editingDraft) { draft in
                NavigationStack { ComposeView(draft: draft) }
            }
    }
}

struct DraftLocationPicker: View {
    @Binding var selection: DraftLocation
    var body: some View {
        HStack(spacing: 2) {
            ForEach(DraftLocation.allCases) { location in
                Button { selection = location } label: {
                    Image(systemName: location == .device ? "iphone" : "icloud")
                        .font(MailStyle.icon).frame(width: 44, height: 44)
                        .foregroundStyle(selection == location ? MailStyle.accent : MailStyle.secondaryInk)
                        .background(selection == location ? MailStyle.accent.opacity(0.12) : .clear, in: .capsule)
                }.buttonStyle(.plain).accessibilityLabel(location.rawValue)
                    .accessibilityAddTraits(selection == location ? .isSelected : [])
            }
        }.padding(.horizontal, 3).modifier(MailControlSurface()).accessibilityIdentifier("draftLocationPicker")
    }
}

/// Shared by the Drafts mailbox and the inbox shortcut; local copies remain editable offline.
struct DraftSections: View {
    var accountID: UUID? = nil
    var location: DraftLocation = .device
    let onEdit: (LocalDraft) -> Void
    @Environment(AppSession.self) private var session
    @Environment(AppRuntime.self) private var runtime
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    @Query private var outgoing: [OutgoingMessage]
    @Query private var links: [StoreMetadata]
    @State private var errorMessage: String?
    @State private var deletingDraft: LocalDraft?
    @State private var deletingRemote: MailMessage?
    @State private var deleting = false
    @State private var refreshing = false
    private var local: [LocalDraft] { session.drafts.filter { accountID == nil || $0.accountID == accountID } }
    private var remote: [MailMessage] {
        let hidden = DraftLinks.hiddenMessageIDs(outgoing: outgoing.filter { $0.stateRaw != "draft" }, links: links, accountID: accountID)
        return messages.filter { $0.isDraft && !$0.isTrash && (accountID == nil || $0.accountID == accountID) && !hidden.contains($0.identity) }
    }
    private func accountName(_ id: UUID?) -> String { accounts.first(where: { $0.id == id })?.email ?? "No account selected" }
    private func hasGmailCopy(_ draft: LocalDraft) -> Bool {
        guard let row = outgoing.first(where: { $0.id == draft.id }), let accountID = row.accountID, let remoteID = row.remoteDraftID else { return false }
        return links.contains { $0.key == DraftLinks.key(accountID, remoteID) }
    }

    var body: some View {
        Group {
            deletionPresenter
            if location == .device && !local.isEmpty {
              Section {
                ForEach(local) { draft in
                Button {
                    onEdit(draft)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.displaySubject).font(.headline).foregroundStyle(.primary)
                        Text(draft.to.isEmpty ? "No recipients" : draft.to)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Text(draft.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        if !draft.attachments.isEmpty {
                            Label("\(draft.attachments.count) attachment\(draft.attachments.count == 1 ? "" : "s")", systemImage: "paperclip")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(accountName(draft.accountID)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack {
                            Text(hasGmailCopy(draft) ? "Local edits · Gmail copy" : "On this device")
                            Spacer()
                            Text(draft.updatedAt, format: .dateTime.month().day().hour().minute())
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("localDraft-\(draft.id.uuidString)")
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete local copy", role: .destructive) { deletingDraft = draft }
                }
                .contextMenu { Button("Delete local copy", systemImage: "trash", role: .destructive) { deletingDraft = draft } }
                }
              } header: {
                Text("On this device")
              } footer: {
                Text("Edits are saved on this device. Use Save to Gmail in the composer to update the Gmail copy.")
              }
            }
            if location == .gmail && !remote.isEmpty {
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
                        .swipeActions(allowsFullSwipe: false) { Button("Delete Gmail draft", role: .destructive) { deletingRemote = message } }
                        .contextMenu { Button("Delete Gmail draft", systemImage: "trash", role: .destructive) { deletingRemote = message } }
                        .disabled(deleting)
                    }
                }
            }
            if location == .device ? local.isEmpty : remote.isEmpty {
                ContentUnavailableView("No drafts", systemImage: "doc", description: Text(location == .device ? "Drafts saved on this device appear here." : "Your Gmail drafts appear here after syncing."))
            }
            if deleting { ProgressView("Deleting draft…") }
            if refreshing && location == .gmail { ProgressView("Updating Gmail drafts…") }
            ForEach(accounts.filter { location == .gmail && (accountID == nil || $0.id == accountID) && runtime.gmail?.hasOlder($0.id, mailbox: "Drafts") == true }) { account in
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
        .listRowBackground(MailStyle.paper)
        .task(id: accountID) { await refresh() }
    }
    // A single stable presenter avoids duplicating dialogs across the Group's list rows.
    private var deletionPresenter: some View {
        Color.clear.frame(height: 0).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
        .confirmationDialog("Delete the local copy?", isPresented: Binding(
            get: { deletingDraft != nil }, set: { if !$0 { deletingDraft = nil } }
        ), titleVisibility: .visible, presenting: deletingDraft) { draft in
            Button("Delete local copy", role: .destructive) {
                do { try session.deleteDraft(id: draft.id) }
                catch { errorMessage = error.localizedDescription }
                deletingDraft = nil
            }
        } message: { _ in Text("Any copy saved in Gmail will remain there.") }
        .confirmationDialog("Delete this Gmail draft?", isPresented: Binding(
            get: { deletingRemote != nil }, set: { if !$0 { deletingRemote = nil } }
        ), titleVisibility: .visible, presenting: deletingRemote) { message in
            Button("Delete Gmail draft", role: .destructive) {
                deletingRemote = nil; deleting = true; errorMessage = nil
                Task {
                    defer { deleting = false }
                    do {
                        guard let gmail = runtime.gmail else { throw GmailError.reconnect }
                        try await gmail.deleteRemoteDraft(message)
                        try session.reloadDrafts()
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        } message: { _ in Text("The Gmail draft and any linked local edits will be deleted. This cannot be undone.") }
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
