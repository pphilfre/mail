import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("showSampleInbox") private var showSamples = false
    @Environment(AppRuntime.self) private var runtime
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    @Query(sort: \MailFolder.name) private var folders: [MailFolder]
    @Query(filter: #Predicate<OutgoingMessage> { $0.stateRaw == "sendUnconfirmed" }) private var uncertain: [OutgoingMessage]
    @State private var accountFilter: UUID?
    @State private var mailbox = "Inbox"
    @State private var labelFilter: String?
    private let mailboxes = ["Inbox", "All Mail", "Unread", "Starred", "Sent", "Drafts", "Archive", "Trash"]
    private var filtered: [MailMessage] {
        messages.filter { row in
            guard accountFilter == nil || row.accountID == accountFilter else { return false }
            if let labelFilter { return row.folderIDs.contains(labelFilter) }
            switch mailbox {
            case "Trash": return row.isTrash
            case "All Mail": return !row.isTrash && !row.isSpam
            case "Unread": return !row.isRead && !row.isTrash && !row.isSpam
            case "Starred": return row.isStarred && !row.isTrash && !row.isSpam
            case "Sent": return row.isSent && !row.isTrash
            case "Drafts": return row.isDraft && !row.isTrash
            case "Archive": return !row.isInbox && !row.isSent && !row.isDraft && !row.isTrash && !row.isSpam
            default: return row.isInbox && !row.isTrash && !row.isSpam
            }
        }
    }

    var body: some View {
        List {
            if let error = session.storageError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if !session.drafts.isEmpty {
                Section {
                    NavigationLink {
                        DraftsView()
                    } label: {
                        Label {
                            HStack {
                                Text("On-device drafts")
                                Spacer()
                                Text(session.drafts.count, format: .number).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "doc") }
                    }
                }
            }
            if !uncertain.isEmpty {
                Section("Check Sent in Gmail") {
                    ForEach(uncertain) { row in
                        VStack(alignment: .leading) {
                            Text(row.subject.isEmpty ? "No subject" : row.subject).font(.headline)
                            Text("Sending was interrupted or could not be confirmed. This copy is kept and will not be resent.").font(.caption).foregroundStyle(.secondary)
                            Text(row.toRaw).font(.caption)
                            Text(row.body).lineLimit(3).textSelection(.enabled)
                            Button("Check Sent") { Task { await runtime.gmail?.confirmSent(row) } }
                        }
                    }
                }
            }
            if let error = runtime.gmail?.error { Text(error).font(.caption).foregroundStyle(.red) }
            if !accounts.isEmpty {
                Section {
                    Picker("Account", selection: $accountFilter) {
                        Text("All Gmail accounts").tag(UUID?.none)
                        ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
                    }
                    Picker("Mailbox", selection: $mailbox) { ForEach(mailboxes, id: \.self) { Text($0) } }
                        .onChange(of: mailbox) { _, _ in labelFilter = nil }
                    if let id = accountFilter {
                        Picker("Label", selection: $labelFilter) {
                            Text("Mailbox selection").tag(String?.none)
                            ForEach(folders.filter { $0.accountID == id && $0.kindRaw == "user" }) { Text($0.name).tag(Optional($0.remoteID)) }
                        }
                    }
                }
                ForEach(accounts.filter { accountFilter == nil || $0.id == accountFilter }) { account in
                    if let error = account.lastSyncError { Text(error).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    ForEach(filtered) { message in
                        NavigationLink { GmailMessageView(message: message) } label: { CachedMessageRow(message: message) }
                            .swipeActions(edge: .leading) {
                                Button(message.isRead ? "Unread" : "Read", systemImage: message.isRead ? "envelope.badge" : "envelope.open") {
                                    runtime.gmail?.action(message.isRead ? "unread" : "read", message: message)
                                }.tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(message.isTrash ? "Restore" : "Trash", systemImage: message.isTrash ? "tray" : "trash", role: .destructive) {
                                    runtime.gmail?.action(message.isTrash ? "restore" : "trash", message: message)
                                }
                                Button("Archive", systemImage: "archivebox") { runtime.gmail?.action("archive", message: message) }.tint(.orange)
                                Button(message.isStarred ? "Unstar" : "Star", systemImage: "star") {
                                    runtime.gmail?.action(message.isStarred ? "unstar" : "star", message: message)
                                }.tint(.yellow)
                            }
                    }
                    if filtered.isEmpty { ContentUnavailableView("No cached messages", systemImage: "tray", description: Text("Pull to refresh, or load older mail below.")) }
                }
                ForEach(accounts.filter { (accountFilter == nil || $0.id == accountFilter) && $0.syncCursor != nil }) { account in
                    Button("Load older mail · \(account.email)") { Task { await runtime.gmail?.loadOlder(account.id) } }
                        .disabled(runtime.gmail?.syncing.contains(account.id) == true)
                }
                if runtime.gmail?.syncing.isEmpty == false { HStack { ProgressView(); Text("Syncing Gmail…").foregroundStyle(.secondary) } }
            } else if showSamples {
                Section {
                    ForEach(session.sampleMessages) { message in
                        NavigationLink {
                            MessageView(message: message)
                        } label: { MessageRow(message: message) }
                    }
                } header: {
                    Text("Sample inbox")
                } footer: {
                    Text("These messages are examples. Turn them off in Settings.")
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Your inbox starts here", systemImage: "tray")
                    } description: {
                        Text("Connect Gmail in Accounts, or explore sample mail in Settings.")
                    }
                    .accessibilityIdentifier("emptyInbox")
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Inbox")
        .onChange(of: mailbox) { _, _ in loadMailbox() }
        .onChange(of: accountFilter) { _, _ in labelFilter = nil; loadMailbox() }
        .onChange(of: labelFilter) { _, _ in loadMailbox() }
        .refreshable {
            await runtime.gmail?.syncAll()
            if !accounts.isEmpty { await runtime.gmail?.loadMailbox(mailbox, accountID: accountFilter, labelID: labelFilter) }
        }
    }
    private func loadMailbox() {
        Task { await runtime.gmail?.loadMailbox(mailbox, accountID: accountFilter, labelID: labelFilter) }
    }
}

struct CachedMessageRow: View {
    let message: MailMessage
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(message.isRead ? Color.clear : MailStyle.accent).frame(width: 8, height: 8).padding(.top, 7)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.sender.displayName).font(.headline).lineLimit(1)
                    Spacer()
                    if message.isStarred { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                    Text(message.receivedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.subject.isEmpty ? "No subject" : message.subject).font(.subheadline).lineLimit(1)
                Text(message.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 5).accessibilityElement(children: .combine).accessibilityValue(message.isRead ? "Read" : "Unread")
    }
}

struct MessageRow: View {
    let message: SampleMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.isRead ? Color.clear : MailStyle.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: MailStyle.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.sender).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(message.date, format: .dateTime.hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(message.subject).font(.subheadline).lineLimit(1)
                Text(message.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityValue(message.isRead ? "Read" : "Unread")
    }
}
