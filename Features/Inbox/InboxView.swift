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
    @AppStorage("selectedMailAccount") private var accountFilterRaw = ""
    @AppStorage("selectedMailbox") private var mailbox = "Inbox"
    private var accountFilter: UUID? { UUID(uuidString: accountFilterRaw) }
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
    private var selectedAccounts: [MailAccount] { accounts.filter { accountFilter == nil || $0.id == accountFilter } }
    private var uncertainCount: Int { uncertain.filter { accountFilter == nil || $0.accountID == accountFilter }.count }
    private var inboxError: String? {
        if let error = session.storageError { return error }
        if !accounts.isEmpty && runtime.connectivity.isConnected == false {
            return "Saved mail is available offline. Mailbox changes will retry when your connection returns."
        }
        return selectedAccounts.first(where: { $0.lastSyncError != nil }).map { "\($0.email): \($0.lastSyncError ?? "")" } ?? runtime.gmail?.error
    }
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
    private var filteredSamples: [SampleMessage] {
        switch mailbox {
        case "Inbox", "All Mail": session.sampleMessages
        case "Unread": session.sampleMessages.filter { !$0.isRead }
        default: []
        }
    }

    var body: some View {
        List {
            if let error = inboxError {
                Section {
                    DisclosureGroup {
                        Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button("Retry") { Task { await runtime.gmail?.syncAll() } }
                            Button("Accounts") { showingAccounts = true }
                        }.buttonStyle(.bordered)
                    } label: {
                        Label(runtime.connectivity.isConnected == false ? "Offline · Saved mail is available" : "Mail needs attention",
                              systemImage: runtime.connectivity.isConnected == false ? "wifi.slash" : "exclamationmark.triangle").font(.subheadline)
                    }
                }
            }
            if mailbox != "Drafts" && session.drafts.contains(where: { accountFilter == nil || $0.accountID == accountFilter }) {
                Section {
                    NavigationLink {
                        DraftsView(accountID: accountFilter)
                    } label: {
                        Label {
                            HStack {
                                Text("Drafts")
                                Spacer()
                                Text("\(session.drafts.filter { accountFilter == nil || $0.accountID == accountFilter }.count) local").foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "doc") }
                    }
                    .accessibilityIdentifier("draftsShortcut")
                }
            }
            if uncertainCount > 0 {
                Section {
                    NavigationLink { OutboxView(accountID: accountFilter) } label: {
                        HStack {
                            Label("Sending needs confirmation", systemImage: "exclamationmark.circle")
                            Spacer()
                            Text(uncertainCount, format: .number).foregroundStyle(.secondary)
                        }.font(.subheadline)
                    }
                }
            }
            if mailbox == "Drafts" && labelFilter == nil {
                DraftSections(accountID: accountFilter)
            } else if !accounts.isEmpty {
                Section {
                    ForEach(filtered) { message in
                        NavigationLink { GmailMessageView(message: message) } label: { CachedMessageRow(message: message) }
                            .accessibilityIdentifier("cachedMessage-\(message.remoteID)")
                            .swipeActions(edge: .leading, allowsFullSwipe: fullSwipe) {
                                swipeButton(leadingSwipe, message: message)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: fullSwipe) {
                                swipeButton(trailingSwipe, message: message)
                            }
                    }
                    if filtered.isEmpty {
                        if selectedAccounts.contains(where: { runtime.gmail?.syncing.contains($0.id) == true }) {
                            HStack { ProgressView(); Text("Loading \(mailbox.lowercased())…").foregroundStyle(.secondary) }
                        } else {
                            ContentUnavailableView(inboxError == nil ? "No messages here" : "Mail couldn’t refresh", systemImage: "tray",
                                description: Text(inboxError == nil ? "Pull to refresh or load older messages." : "Your downloaded mail is kept. Open the status above to retry."))
                        }
                    }
                }
                ForEach(selectedAccounts.filter { runtime.gmail?.hasOlder($0.id, mailbox: mailbox, labelID: labelFilter) == true }) { account in
                    Button(selectedAccounts.count == 1 ? "Load older messages" : "Load older · \(account.email)") {
                        Task { await runtime.gmail?.loadOlder(account.id, mailbox: mailbox, labelID: labelFilter) }
                    }
                        .disabled(runtime.gmail?.syncing.contains(account.id) == true)
                }
                if !filtered.isEmpty && selectedAccounts.contains(where: { runtime.gmail?.syncing.contains($0.id) == true }) {
                    HStack { ProgressView(); Text("Updating mail…").foregroundStyle(.secondary) }.font(.caption)
                }
            } else if showSamples {
                Section {
                    ForEach(filteredSamples) { message in
                        NavigationLink {
                            MessageView(message: message)
                        } label: { MessageRow(message: message) }
                    }
                    if filteredSamples.isEmpty {
                        ContentUnavailableView("No sample messages here", systemImage: "tray",
                            description: Text("Explore Inbox, All Mail, or Unread to see sample mail."))
                            .listRowBackground(Color.clear)
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
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(labelFilter.flatMap { id in folders.first { $0.remoteID == id && $0.accountID == accountFilter }?.name } ?? mailbox).font(.headline)
                    if let selected = accounts.first(where: { $0.id == accountFilter }) {
                        Text(selected.email).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    } else if accounts.count > 1 {
                        Text("All accounts").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
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
        .task {
            if !mailboxes.contains(mailbox) { mailbox = "Inbox" }
            if let selected = accountFilter, !accounts.contains(where: { $0.id == selected }) { accountFilterRaw = "" }
            loadMailbox()
        }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selected = accountFilter, !ids.contains(selected) { accountFilterRaw = "" }
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
                    Button { accountFilterRaw = "" } label: { drawerLabel("All accounts", symbol: "tray.2", selected: accountFilter == nil) }
                    ForEach(accounts) { account in
                        Button { accountFilterRaw = account.id.uuidString } label: {
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
        // The unified drafts section owns its initial load and provider-link refresh.
        guard mailbox != "Drafts" || labelFilter != nil else { return }
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
                    MailRowDate(date: message.receivedAt)
                }
                Text(message.subject.isEmpty ? "No subject" : message.subject).font(.subheadline).lineLimit(1)
                if previewLines > 0 { Text(message.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(previewLines) }
            }
        }.padding(.vertical, 5).accessibilityElement(children: .combine).accessibilityValue(message.isRead ? "Read" : "Unread")
    }
}

struct MessageRow: View {
    let message: SampleMessage
    @AppStorage("previewLines") private var previewLines = 2

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
                    MailRowDate(date: message.date)
                }
                Text(message.subject).font(.subheadline).lineLimit(1)
                if previewLines > 0 { Text(message.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(previewLines) }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityValue(message.isRead ? "Read" : "Unread")
    }
}
