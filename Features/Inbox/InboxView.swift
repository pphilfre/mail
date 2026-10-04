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
    @State private var showingDrawer = false
    @State private var showingAccounts = false
    @State private var showingSettings = false
    @State private var showingSearch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("leadingSwipe") private var leadingSwipe = "read"
    @AppStorage("trailingSwipe") private var trailingSwipe = "archive"
    @AppStorage("fullSwipe") private var fullSwipe = false
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
                ForEach(accounts.filter { accountFilter == nil || $0.id == accountFilter }) { account in
                    if let error = account.lastSyncError { Text(error).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    ForEach(filtered) { message in
                        NavigationLink { GmailMessageView(message: message) } label: { CachedMessageRow(message: message) }
                            .swipeActions(edge: .leading, allowsFullSwipe: fullSwipe) {
                                swipeButton(leadingSwipe, message: message)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: fullSwipe) {
                                swipeButton(trailingSwipe, message: message)
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
        .listStyle(.plain)
        .navigationTitle(labelFilter.flatMap { id in folders.first { $0.remoteID == id && $0.accountID == accountFilter }?.name } ?? mailbox)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Mailboxes", systemImage: "line.3.horizontal") { toggleDrawer() }
                    .accessibilityIdentifier("mailboxDrawerButton")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Search", systemImage: "magnifyingglass") { showingSearch = true }
                    .accessibilityIdentifier("searchButton")
            }
        }
        .overlay(alignment: .leading) {
            if showingDrawer {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.22).ignoresSafeArea()
                            .onTapGesture { toggleDrawer() }
                            .accessibilityLabel("Close mailboxes")
                            .accessibilityAddTraits(.isButton)
                        drawer.frame(width: min(340, geometry.size.width * 0.88))
                            .frame(maxHeight: .infinity)
                            .background(.regularMaterial)
                            .transition(.move(edge: .leading))
                    }
                }
            }
        }
        .sheet(isPresented: $showingAccounts) {
            NavigationStack { AccountsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAccounts = false } } } }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } } }
        }
        .sheet(isPresented: $showingSearch) {
            NavigationStack { LocalSearchView(initialAccountID: accountFilter) }
        }
        .onChange(of: mailbox) { _, _ in loadMailbox() }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selected = accountFilter, !ids.contains(selected) { accountFilter = nil }
        }
        .onChange(of: accountFilter) { _, _ in labelFilter = nil; loadMailbox() }
        .onChange(of: labelFilter) { _, _ in loadMailbox() }
        .refreshable {
            await runtime.gmail?.syncAll()
            if !accounts.isEmpty { await runtime.gmail?.loadMailbox(mailbox, accountID: accountFilter, labelID: labelFilter) }
        }
    }
    private func toggleDrawer() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { showingDrawer.toggle() }
    }
    @ViewBuilder private func swipeButton(_ value: String, message: MailMessage) -> some View {
        if let action = MailSwipeAction(rawValue: value), action != .none {
            Button(action.label(for: message), systemImage: action.symbol) {
                runtime.gmail?.action(action.operation(for: message), message: message)
            }.tint(action.tint)
        }
    }
    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Dispatch").font(.title2.bold())
                Spacer()
                Button("Close", systemImage: "xmark") { toggleDrawer() }.labelStyle(.iconOnly).buttonStyle(.glass)
            }.padding(20)
            List {
                Section("Accounts") {
                    Button { accountFilter = nil } label: { drawerLabel("All accounts", symbol: "tray.2", selected: accountFilter == nil) }
                    ForEach(accounts) { account in
                        Button { accountFilter = account.id } label: {
                            drawerLabel(account.email, symbol: "person.crop.circle", selected: accountFilter == account.id)
                        }
                    }
                }
                Section("Mailboxes") {
                    ForEach(mailboxes, id: \.self) { name in
                        Button { labelFilter = nil; mailbox = name; toggleDrawer() } label: {
                            drawerLabel(name, symbol: mailboxSymbol(name), selected: mailbox == name && labelFilter == nil)
                        }
                    }
                }
                if let id = accountFilter {
                    Section("Labels") {
                        ForEach(folders.filter { $0.accountID == id && $0.kindRaw == "user" }) { folder in
                            Button { labelFilter = folder.remoteID; toggleDrawer() } label: {
                                drawerLabel(folder.name, symbol: "tag", selected: labelFilter == folder.remoteID)
                            }
                        }
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
            Divider()
            HStack {
                Button("Accounts", systemImage: "person.crop.circle") { toggleDrawer(); showingAccounts = true }
                Spacer()
                Button("Settings", systemImage: "gearshape") { toggleDrawer(); showingSettings = true }
            }.font(.subheadline).padding(20)
        }
    }
    private func drawerLabel(_ title: String, symbol: String, selected: Bool) -> some View {
        HStack {
            Label(title, systemImage: symbol).lineLimit(1)
            Spacer()
            if selected { Image(systemName: "checkmark").font(.caption.bold()) }
        }.foregroundStyle(selected ? MailStyle.accent : Color.primary)
    }
    private func mailboxSymbol(_ name: String) -> String {
        switch name {
        case "Inbox": "tray"
        case "All Mail": "tray.2"
        case "Unread": "envelope.badge"
        case "Starred": "star"
        case "Sent": "paperplane"
        case "Drafts": "doc"
        case "Archive": "archivebox"
        default: "trash"
        }
    }
    private func loadMailbox() {
        Task { await runtime.gmail?.loadMailbox(mailbox, accountID: accountFilter, labelID: labelFilter) }
    }
}

struct CachedMessageRow: View {
    let message: MailMessage
    @AppStorage("previewLines") private var previewLines = 2
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SenderAvatar(email: message.senderEmail, name: message.sender.displayName)
                .overlay(alignment: .bottomTrailing) {
                    if !message.isRead { Circle().fill(MailStyle.accent).frame(width: 9, height: 9).overlay(Circle().stroke(.background, lineWidth: 2)) }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.sender.displayName).font(.system(.headline, weight: message.isRead ? .medium : .bold)).lineLimit(1)
                    Spacer()
                    if message.isStarred { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                    Text(message.receivedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.subject.isEmpty ? "No subject" : message.subject).font(.subheadline).lineLimit(1)
                if previewLines > 0 { Text(message.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(previewLines) }
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
