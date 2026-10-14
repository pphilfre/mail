import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("showSampleInbox") private var showSamples = false
    @Environment(AppRuntime.self) private var runtime
    @Environment(MailFeedback.self) private var feedback
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    @Query(sort: \MailFolder.name) private var folders: [MailFolder]
    @Query private var attachments: [MailAttachment]
    @Query private var metadata: [StoreMetadata]
    @Query private var outgoing: [OutgoingMessage]
    @Query private var operations: [PendingMailOperation]
    @AppStorage("selectedMailAccount") private var accountFilterRaw = ""
    @AppStorage("selectedMailbox") private var mailbox = "Inbox"
    private var accountFilter: UUID? { UUID(uuidString: accountFilterRaw) }
    @State private var labelFilter: String?
    @State private var showingDrawer = false
    @State private var refreshing = false
    @State private var showingAccounts = false
    @State private var showingSettings = false
    @State private var showingSearch = false
    @State private var showingCompose = false
    @State private var editingDraft: LocalDraft?
    @State private var draftLocation = DraftLocation.device
    @State private var showingTasks = false
    @State private var showingReceipts = false
    @State private var showingAttachments = false
    @State private var showingPeople = false
    @State private var showingCollections = false
    @State private var showingSubscriptions = false
    @State private var quickFilter = InboxQuickFilter.all
    @State private var sheetDestination: SheetDestination?
    private enum SheetDestination { case accounts, settings, tasks, receipts, attachments, people, collections, subscriptions, search }
    @State private var selecting = false
    @State private var selectedIDs = Set<String>()
    @State private var confirmingTrash = false
    @AppStorage("conversationRows") private var conversationRows = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("leadingSwipe") private var leadingSwipe = "read"
    @AppStorage("trailingSwipe") private var trailingSwipe = "archive"
    @AppStorage("fullSwipe") private var fullSwipe = false
    @AppStorage("compactInbox") private var compactInbox = false
    @AppStorage("previewLines") private var previewLines = 2
    @State private var organisationNow = Date()
    private var organisation: [String: MailLocalOrganisation] { MailLocalOrganisation.values(metadata) }
    private var nextSnoozeDeadline: Date? {
        organisation.values.compactMap(\.snoozedUntil).filter { $0 > organisationNow }.min()
    }
    private var openTaskCount: Int {
        metadata.filter { $0.key.hasPrefix("mail-task:") }.compactMap { try? MailTask.decode($0) }
            .filter { !$0.isCompleted && ($0.isStandalone || accountFilter == nil || $0.accountID == accountFilter) }.count
    }
    private let mailboxes = MailboxScope.names
    private var selectedAccounts: [MailAccount] { accounts.filter { accountFilter == nil || $0.id == accountFilter } }
    private var waitingUntil: Date? { selectedAccounts.compactMap { runtime.gmail?.waitingUntil[$0.id] }.filter { $0 > Date() }.max() }
    private var uncertainCount: Int { outgoing.filter { ["scheduled", "sendFailed", "sendUnconfirmed"].contains($0.stateRaw) && (accountFilter == nil || $0.accountID == accountFilter) }.count }
    private var inboxError: String? {
        if let error = session.storageError { return error }
        if !accounts.isEmpty && runtime.connectivity.isConnected == false {
            return "Saved mail is available offline. Mailbox changes will retry when your connection returns."
        }
        return selectedAccounts.first(where: { $0.lastSyncError != nil }).map { "\($0.email): \($0.lastSyncError ?? "")" } ?? runtime.gmail?.error
    }
    @AppStorage("savedMailSearches") private var savedRaw = "[]"
    private var smartSearch: SavedMailSearch? {
        guard let labelFilter, labelFilter.hasPrefix("smart:") else { return nil }
        return SavedMailSearch.decode(savedRaw).first { $0.id.uuidString == String(labelFilter.dropFirst(6)) }
    }
    private var filtered: [MailMessage] {
        if let search = smartSearch {
            let filesByMessage = Dictionary(grouping: attachments, by: \.messageID)
            let foldersByAccount = Dictionary(grouping: folders, by: \.accountID)
            let docs = messages.map { message in
                let files = filesByMessage[message.id] ?? []
                let labels = (foldersByAccount[message.accountID] ?? []).filter { message.folderIDs.contains($0.remoteID) }.map(\.name)
                return MailSearchDocument(id: message.id, accountID: message.accountID,
                    fields: [message.subject, message.snippet, message.senderEmail, message.sender.displayName] + files.map(\.filename) + labels,
                    isTrash: message.isTrash, isSpam: message.isSpam, sender: message.sender.displayName + " " + message.senderEmail,
                    recipients: (message.to + message.cc + message.bcc).map(\.email), subject: message.subject,
                    labels: labels + message.folderIDs, receivedAt: message.receivedAt, isRead: message.isRead,
                    isStarred: message.isStarred, hasAttachments: !files.isEmpty)
            }
            let ids = Set(MailSearchIndex(documents: docs).matches(search.query, accountID: search.accountID,
                includeTrashAndSpam: search.includeTrashAndSpam, filters: search.filters))
            return messages.filter { ids.contains($0.id) }
        }
        return messages.filter { row in
            guard accountFilter == nil || row.accountID == accountFilter else { return false }
            return MailboxScope.contains(row, mailbox: mailbox, labelID: labelFilter)
        }
    }
    private var conversations: [MailConversation] {
        let saved = organisation
        return MailConversation.rows(filtered, grouped: conversationRows).filter {
            let value = saved[MailLocalOrganisation.key($0.latest)] ?? MailLocalOrganisation()
            let visible = value.isVisible(mailbox: mailbox, hasLabelFilter: labelFilter != nil, at: organisationNow)
            return visible && (quickFilter == .all || (quickFilter == .unread ? !$0.isRead : $0.isStarred))
        }.sorted {
            let lhs = saved[MailLocalOrganisation.key($0.latest)]?.pinned == true
            let rhs = saved[MailLocalOrganisation.key($1.latest)]?.pinned == true
            if lhs != rhs { return lhs }
            if $0.latest.receivedAt != $1.latest.receivedAt { return $0.latest.receivedAt > $1.latest.receivedAt }
            return $0.id < $1.id
        }
    }
    private var selectedMessages: [MailMessage] { conversations.filter { selectedIDs.contains($0.id) }.flatMap(\.messages) }
    private var attachmentMessageIDs: Set<UUID> { Set(attachments.map(\.messageID)) }
    private var failedCount: Int { operations.filter { $0.lastError != nil && (accountFilter == nil || $0.accountID == accountFilter) }.count }
    private var filteredSamples: [SampleMessage] {
        session.sampleMessages.filter {
            (mailbox == "Inbox" || mailbox == "All Mail" || (mailbox == "Unread" && !$0.isRead)) &&
            (quickFilter == .all || (quickFilter == .unread && !$0.isRead))
        }
    }
    private var mailboxTitle: String {
        let base = smartSearch?.name ?? labelFilter.flatMap { id in folders.first { $0.remoteID == id && $0.accountID == accountFilter }?.name } ?? mailbox
        return quickFilter == .all ? base : "\(quickFilter.rawValue) · \(base)"
    }
    private var activeFilter: Binding<InboxQuickFilter> {
        Binding(get: {
            if labelFilter == nil && mailbox == "Unread" { return .unread }
            if labelFilter == nil && mailbox == "Starred" { return .starred }
            return quickFilter
        }, set: { value in
            if labelFilter == nil && ["Inbox", "Unread", "Starred"].contains(mailbox) {
                quickFilter = .all
                mailbox = value == .all ? "Inbox" : value.rawValue
            } else { quickFilter = value }
        })
    }
    private var scopeTitle: String {
        accounts.first { $0.id == accountFilter }?.email ?? (accounts.isEmpty ? "Sample inbox" : "All accounts")
    }

    var body: some View {
        Group {
            if mailbox == "Catch Up" && labelFilter == nil { LocalMailOverview(accountID: accountFilter) }
            else {
                // A new scope starts at the top with fresh row heights; chrome remains mounted.
                mailList.id("mailbox-\(mailbox)-\(labelFilter ?? "")-\(accountFilterRaw)")
            }
        }
        // Recreate the list's size cache when reading density changes, rather than keeping old cell heights.
        .id("mail-density-\(compactInbox)-\(previewLines)")
        .listStyle(.plain)
        .listRowSeparatorTint(MailStyle.divider)
        .scrollContentBackground(.hidden)
        .background(MailStyle.paper)
        // Swap mailbox contents without animating recycled list cells through the header.
        .animation(nil, value: mailbox)
        .animation(nil, value: labelFilter)
        .foregroundStyle(MailStyle.ink)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, compactInbox ? 44 : 48)
        .environment(\.editMode, .constant(selecting ? .active : .inactive))
        .safeAreaInset(edge: .bottom) {
            if selecting { bulkToolbar }
            else {
                HStack {
                    Spacer()
                    MailGlassButton(title: "Compose", symbol: "square.and.pencil") { showingCompose = true }
                        .accessibilityIdentifier("composeButton")
                }.padding(.horizontal, MailStyle.contentPadding).padding(.vertical, 8)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { inboxHeader }
        .confirmationDialog("Move \(selectedMessages.count) loaded messages to Trash?", isPresented: $confirmingTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { bulkAction("trash") }
        }
        .navigationTitle(mailboxTitle)
        .task(id: nextSnoozeDeadline) {
            guard let deadline = nextSnoozeDeadline else { return }
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled else { return }
            organisationNow = Date()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if mailbox == "Drafts" && labelFilter == nil {
                    HStack(spacing: 8) { MailNavigationTitle(title: "Drafts"); DraftLocationPicker(selection: $draftLocation) }
                }
                else { MailNavigationTitle(title: mailboxTitle) }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Mailboxes", systemImage: "line.3.horizontal") { toggleDrawer() }
                    .accessibilityIdentifier("mailboxDrawerButton")
                    .disabled(showingDrawer)
            }
            ToolbarItem(placement: .topBarLeading) {
                profileMenu
                    .disabled(showingDrawer)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Settings", systemImage: "gearshape") { feedback.select(); showingSettings = true }
                    .labelStyle(.iconOnly).accessibilityIdentifier("settingsButton")
                    .disabled(showingDrawer)
            }
        }
        .fullScreenCover(isPresented: $showingDrawer, onDismiss: presentDestination) { mailboxPanel }
        .sheet(isPresented: $showingAccounts) {
            NavigationStack { AccountsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAccounts = false } } } }
                .modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } } }
                .modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingSearch) {
            NavigationStack { LocalSearchView(initialAccountID: accountFilter, onClose: {
                mailbox = "Inbox"; labelFilter = nil; quickFilter = .all; showingSearch = false
            }) }
        }
        .sheet(isPresented: $showingCompose) {
            NavigationStack { ComposeView(draft: LocalDraft(accountID: accountFilter)) }
        }
        .sheet(item: $editingDraft) { draft in
            NavigationStack { ComposeView(draft: draft) }
        }
        .navigationDestination(isPresented: $showingTasks) {
            MailTasksView(accountID: accountFilter)
        }
        .sheet(isPresented: $showingReceipts) {
            NavigationStack {
                ReceiptsView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { showingReceipts = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingAttachments) {
            NavigationStack {
                AttachmentLibraryView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { showingAttachments = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingPeople) {
            NavigationStack {
                PeopleView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { showingPeople = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingCollections) {
            NavigationStack {
                CollectionsView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { showingCollections = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingSubscriptions) {
            NavigationStack {
                SubscriptionsView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        MailCloseButton { showingSubscriptions = false }.accessibilityIdentifier("closeSubscriptionsButton")
                    } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .onChange(of: mailbox) { _, _ in quickFilter = .all; loadMailbox() }
        .task {
            if !mailboxes.contains(mailbox) && mailbox != "Catch Up" { mailbox = "Inbox" }
            if let selected = accountFilter, !accounts.contains(where: { $0.id == selected }) { accountFilterRaw = "" }
            loadMailbox()
        }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selected = accountFilter, !ids.contains(selected) { accountFilterRaw = "" }
        }
        .onChange(of: accountFilter) { _, _ in
            if smartSearch == nil || smartSearch?.accountID != accountFilter { labelFilter = nil }
            quickFilter = .all; loadMailbox()
        }
        .onChange(of: labelFilter) { _, _ in quickFilter = .all; loadMailbox() }
        .onChange(of: quickFilter) { _, _ in selectedIDs.removeAll() }
        .onChange(of: conversationRows) { _, _ in selectedIDs.removeAll() }
        .refreshable {
            refreshing = true
            defer { refreshing = false }
            await runtime.gmail?.syncAll()
            if smartSearch == nil && !accounts.isEmpty && !["Snoozed", "Catch Up"].contains(mailbox) { await runtime.gmail?.loadMailbox(mailbox, accountID: accountFilter, labelID: labelFilter) }
        }
    }
    private var mailList: some View {
        return List(selection: $selectedIDs) {
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
            if uncertainCount > 0 {
                Section {
                    NavigationLink { OutboxView(accountID: accountFilter) } label: {
                        HStack {
                            Label("Outbox", systemImage: "paperplane")
                            Spacer()
                            Text(uncertainCount, format: .number).foregroundStyle(.secondary)
                        }.font(.subheadline)
                    }
                }
            }
            if failedCount > 0 {
                NavigationLink { PendingActionsView(accountID: accountFilter) } label: {
                    Label("\(failedCount) mailbox changes need attention", systemImage: "arrow.triangle.2.circlepath").font(.subheadline)
                }
            }
            if mailbox == "Drafts" && labelFilter == nil {
                DraftSections(accountID: accountFilter, location: draftLocation, onEdit: { editingDraft = $0 })
            } else if !accounts.isEmpty {
                cachedMailSection
            } else if showSamples {
                Section {
                    ForEach(filteredSamples) { message in
                        NavigationLink {
                            MessageView(message: message)
                        } label: { MessageRow(message: message) }
                        .listRowBackground(MailStyle.paper)
                        .listRowInsets(EdgeInsets(top: 0, leading: MailStyle.contentPadding, bottom: 0, trailing: MailStyle.contentPadding))
                    }
                    if filteredSamples.isEmpty {
                        ContentUnavailableView("No sample messages here", systemImage: "tray",
                            description: Text("Explore Inbox, All Mail, or Unread to see sample mail."))
                            .listRowBackground(Color.clear)
                    }
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
    }
    private var cachedMailSection: some View {
        let rows = conversations
        let saved = organisation
        let files = attachmentMessageIDs
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        return Group {

                Section {
                    ForEach(rows) { conversation in
                        if selecting {
                            conversationRow(conversation, saved: saved, files: files, accounts: accountByID).tag(conversation.id)
                        } else {
                            NavigationLink { GmailMessageView(message: conversation.latest) } label: { conversationRow(conversation, saved: saved, files: files, accounts: accountByID) }
                                .accessibilityIdentifier("cachedMessage-\(conversation.latest.remoteID)")
                                .swipeActions(edge: .leading, allowsFullSwipe: fullSwipe) {
                                    conversationSwipe(leadingSwipe, conversation: conversation)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: fullSwipe) {
                                    conversationSwipe(trailingSwipe, conversation: conversation)
                                }
                                .contextMenu {
                                    Button(conversation.isRead ? "Mark unread" : "Mark read") { triage(conversation.isRead ? "unread" : "read", conversation.messages) }
                                    Button(conversation.isStarred ? "Unflag" : "Flag", systemImage: "flag") { triage(conversation.isStarred ? "unstar" : "star", conversation.messages) }
                                    Button("Archive", systemImage: "archivebox") { triage("archive", conversation.messages) }
                                    Button("Delete", systemImage: "trash", role: .destructive) { triage("trash", conversation.messages) }
                                    Button(conversation.latest.isSpam ? "Not spam" : "Move to Spam") { triage(conversation.latest.isSpam ? "notSpam" : "spam", conversation.messages) }
                                }
                        }
                    }
                    .listRowBackground(MailStyle.paper)
                    .listRowInsets(EdgeInsets(top: 0, leading: MailStyle.contentPadding, bottom: 0, trailing: MailStyle.contentPadding))
                    if rows.isEmpty {
                        if selectedAccounts.contains(where: { runtime.gmail?.syncing.contains($0.id) == true }) {
                            HStack { ProgressView(); Text("Loading \(mailbox.lowercased())…").foregroundStyle(.secondary) }
                        } else {
                            ContentUnavailableView(inboxError == nil ? (quickFilter == .unread ? "All caught up" : "No messages here") : "Mail couldn’t refresh",
                                systemImage: quickFilter == .unread && inboxError == nil ? "checkmark.circle" : "tray",
                                description: Text(inboxError == nil ? "Try another filter, pull to refresh, or load older mail." : "Your downloaded mail is kept. Open the status above to retry."))
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                ForEach(selectedAccounts.filter { smartSearch == nil && (mailbox != "Snoozed" || labelFilter != nil) && runtime.gmail?.hasOlder($0.id, mailbox: mailbox, labelID: labelFilter) == true }) { account in
                    Button {
                        Task { await runtime.gmail?.loadOlder(account.id, mailbox: mailbox, labelID: labelFilter) }
                    } label: {
                        HStack(spacing: 8) {
                            if runtime.gmail?.syncing.contains(account.id) == true { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.down") }
                            Text(selectedAccounts.count == 1 ? "Load older messages" : "Load older · \(account.email)").lineLimit(2)
                        }.font(.subheadline.weight(.medium)).foregroundStyle(MailStyle.accent)
                            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 12)
                            .background(MailStyle.tile, in: .rect(cornerRadius: MailStyle.controlRadius))
                    }
                        .buttonStyle(.plain).listRowSeparator(.hidden).padding(.vertical, 10)
                        .disabled(runtime.gmail?.syncing.contains(account.id) == true)
                }
                if !filtered.isEmpty && selectedAccounts.contains(where: { runtime.gmail?.syncing.contains($0.id) == true }) {
                    HStack { ProgressView(); Text("Updating mail…").foregroundStyle(.secondary) }.font(.caption)
                }
        }
    }
    private var inboxHeader: some View {
        InboxHeader(
            filter: activeFilter, mailbox: Binding(get: { labelFilter == nil ? mailbox : "Custom" }, set: { value in
                guard value != "Custom" else { return }
                labelFilter = nil; quickFilter = .all; mailbox = value
            }),
            scopeTitle: mailboxTitle, showFilters: !["Drafts", "Catch Up"].contains(mailbox), allowStarred: !accounts.isEmpty,
            canSelect: !accounts.isEmpty && !["Drafts", "Catch Up"].contains(mailbox), selecting: selecting,
            select: {
                feedback.select()
                withAnimation(MailStyle.motion(reduced: reduceMotion)) { selecting.toggle(); selectedIDs.removeAll() }
            }, updating: refreshing || selectedAccounts.contains { runtime.gmail?.syncing.contains($0.id) == true }, waitingUntil: waitingUntil)
    }
    private var profileMenu: some View {
        Menu {
            Picker("Account", selection: $accountFilterRaw) {
                Text("All accounts").tag("")
                ForEach(accounts) { Text($0.email).tag($0.id.uuidString) }
            }
            Button("Manage accounts", systemImage: "person.crop.circle") { showingAccounts = true }
        } label: {
            Image(systemName: "person.crop.circle").font(MailStyle.icon).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Account: " + scopeTitle)
        .accessibilityIdentifier("profileMenuButton")
    }
    private var mailboxPanel: some View {
    MailSidebarPresentation(dismiss: { setDrawer(false) }) { close in
        MailboxPanel(accounts: accounts, folders: folders,
            counts: Dictionary(uniqueKeysWithValues: mailboxes.map { name in
                (name, name == "Drafts" ? draftCount : accounts.isEmpty && showSamples ? sampleUnread(name) : cachedUnread(accountID: accountFilter, mailbox: name))
            }), accountCounts: accountUnreadCounts, labelCounts: labelUnreadCounts,
            account: $accountFilterRaw, mailbox: $mailbox, label: $labelFilter,
            openAccounts: { sheetDestination = .accounts; close() },
            openSettings: { sheetDestination = .settings; close() },
            openTasks: { sheetDestination = .tasks; close() },
            openReceipts: { sheetDestination = .receipts; close() },
            openAttachments: { sheetDestination = .attachments; close() },
            openPeople: { sheetDestination = .people; close() },
            openCollections: { sheetDestination = .collections; close() },
            openSearch: { sheetDestination = .search; close() },
            openSubscriptions: { sheetDestination = .subscriptions; close() },
            close: close)
    }.presentationBackground(.clear)
    }
    private func presentDestination() {
        switch sheetDestination {
        case .search: showingSearch = true
        case .accounts: showingAccounts = true
        case .settings: showingSettings = true
        case .tasks: showingTasks = true
        case .receipts: showingReceipts = true
        case .attachments: showingAttachments = true
        case .people: showingPeople = true
        case .collections: showingCollections = true
        case .subscriptions: showingSubscriptions = true
        case nil: break
        }
        sheetDestination = nil
    }
    private func sampleUnread(_ name: String) -> Int {
        ["Inbox", "All Mail", "Unread"].contains(name) ? session.sampleMessages.filter { !$0.isRead }.count : 0
    }
    private func toggleDrawer() {
        feedback.select(); setDrawer(!showingDrawer)
    }
    private func setDrawer(_ visible: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { showingDrawer = visible }
    }
    private func loadMailbox() {
        selecting = false; selectedIDs.removeAll()
        // The unified drafts section owns its initial load and provider-link refresh.
        guard smartSearch == nil else { return }
        guard mailbox != "Drafts" || labelFilter != nil else { return }
        guard mailbox != "Snoozed" || labelFilter != nil else { return }
        guard mailbox != "Catch Up" else { return }
        Task { await runtime.gmail?.loadMailbox(mailbox, accountID: accountFilter, labelID: labelFilter) }
    }

    private var draftCount: Int {
        let local = session.drafts.filter { accountFilter == nil || $0.accountID == accountFilter }.count
        let hidden = DraftLinks.hiddenMessageIDs(outgoing: outgoing, links: metadata, accountID: accountFilter)
        return local + messages.filter { $0.isDraft && !$0.isTrash && (accountFilter == nil || $0.accountID == accountFilter) && !hidden.contains($0.identity) }.count
    }
    private func cachedUnread(accountID: UUID?, mailbox: String, labelID: String? = nil) -> Int {
        let saved = organisation
        return messages.filter {
            let value = saved[MailLocalOrganisation.key($0)] ?? MailLocalOrganisation()
            let visible = value.isVisible(mailbox: mailbox, hasLabelFilter: labelID != nil, at: organisationNow)
            return visible && (accountID == nil || $0.accountID == accountID) && !$0.isRead && MailboxScope.contains($0, mailbox: mailbox, labelID: labelID)
        }.count
    }
    private var accountUnreadCounts: [UUID: Int] {
        messages.reduce(into: [:]) { counts, row in
            if !row.isRead && MailboxScope.contains(row, mailbox: "Inbox") { counts[row.accountID, default: 0] += 1 }
        }
    }
    private var labelUnreadCounts: [String: Int] {
        messages.reduce(into: [:]) { counts, row in
            if !row.isRead && (accountFilter == nil || row.accountID == accountFilter) {
                for id in row.folderIDs { counts[id, default: 0] += 1 }
            }
        }
    }
    private func conversationRow(_ conversation: MailConversation, saved: [String: MailLocalOrganisation], files: Set<UUID>, accounts: [UUID: MailAccount]) -> some View {
        CachedMessageRow(message: conversation.latest, messageCount: conversation.messages.count,
            unread: !conversation.isRead, starred: conversation.isStarred,
            hasAttachments: conversation.messages.contains { files.contains($0.id) },
            account: accounts.count > 1 ? accounts[conversation.latest.accountID] : nil,
            pinned: saved[MailLocalOrganisation.key(conversation.latest)]?.pinned == true)
    }
    @ViewBuilder private func conversationSwipe(_ raw: String, conversation: MailConversation) -> some View {
        if let action = MailSwipeAction(rawValue: raw), action != .none {
            let kind = action == .read ? (conversation.isRead ? "unread" : "read") : action == .star ? (conversation.isStarred ? "unstar" : "star") : action.operation(for: conversation.latest)
            Button { triage(kind, conversation.messages) } label: { Label(action.title, systemImage: action.symbol) }.tint(action.tint)
        }
    }
    private var bulkToolbar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(selectedMessages.count) loaded messages selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(selectedIDs.count == conversations.count ? "Clear" : "Select all") {
                    selectedIDs = selectedIDs.count == conversations.count ? [] : Set(conversations.map(\.id))
                }.font(.caption)
            }
            HStack {
                Button("Archive", systemImage: "archivebox") { bulkAction("archive") }
                Spacer()
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Mark read") { bulkAction("read") }
                    Button("Mark unread") { bulkAction("unread") }
                    Button("Star") { bulkAction("star") }
                    Button("Unstar") { bulkAction("unstar") }
                    Button(mailbox == "Spam" ? "Not spam" : "Move to Spam") { bulkAction(mailbox == "Spam" ? "notSpam" : "spam") }
                    if mailbox == "Trash" { Button("Restore") { bulkAction("restore") } }
                    if let id = Set(selectedMessages.map(\.accountID)).first, Set(selectedMessages.map(\.accountID)).count == 1 {
                        Menu("Add label") {
                            ForEach(folders.filter { $0.accountID == id && $0.kindRaw == "user" }) { folder in
                                Button(folder.name) { bulkAction("labelAdd:" + folder.remoteID) }
                            }
                        }
                    }
                }
                Spacer()
                Button("Trash", systemImage: "trash") { confirmingTrash = true }.tint(.red)
            }.disabled(selectedMessages.isEmpty)
        }.padding().background(.regularMaterial)
    }
    private func bulkAction(_ kind: String) {
        let snapshot = selectedMessages
        triage(kind, snapshot); selectedIDs.removeAll(); selecting = false
    }
    private func triage(_ kind: String, _ snapshot: [MailMessage]) {
        feedback.triageKind = kind
        if let gmail = runtime.gmail { gmail.action(kind, messages: snapshot) }
        else {
            do { try runtime.repository?.enqueueBatch(kind, messages: snapshot) }
            catch { session.storageError = error.localizedDescription }
        }
    }
}

struct CachedMessageRow: View {
    let message: MailMessage
    var messageCount = 1
    var unread: Bool? = nil
    var starred: Bool? = nil
    var hasAttachments = false
    var account: MailAccount? = nil
    var pinned = false
    private var isRead: Bool { !(unread ?? !message.isRead) }
    @AppStorage("previewLines") private var previewLines = 2
    @AppStorage("compactInbox") private var compactInbox = false
    var body: some View {
        MailMessageRowContent(sender: message.sender.displayName, email: message.senderEmail,
            subject: message.subject, preview: message.snippet, date: message.receivedAt, isRead: isRead,
            compact: compactInbox, previewLines: previewLines, messageCount: messageCount,
            starred: starred ?? message.isStarred, hasAttachments: hasAttachments, pinned: pinned, account: account)
    }
}

struct MessageRow: View {
    let message: SampleMessage
    @AppStorage("previewLines") private var previewLines = 2
    @AppStorage("compactInbox") private var compactInbox = false

    var body: some View {
        MailMessageRowContent(sender: message.sender, email: message.address, subject: message.subject,
            preview: message.snippet, date: message.date, isRead: message.isRead,
            compact: compactInbox, previewLines: previewLines, allowsRemoteIcon: false)
    }
}

/// Real mail, sample mail and search use the same reading rhythm and state cues.
private struct MailMessageRowContent: View {
    let sender: String
    let email: String
    let subject: String
    let preview: String
    let date: Date
    let isRead: Bool
    let compact: Bool
    let previewLines: Int
    var messageCount = 1
    var starred = false
    var hasAttachments = false
    var pinned = false
    var account: MailAccount? = nil
    var allowsRemoteIcon = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SenderAvatar(email: email, name: sender, allowsRemoteIcon: allowsRemoteIcon, size: compact ? 32 : 36, context: subject)
                .overlay(alignment: .bottomTrailing) {
                    if !isRead {
                        Circle().fill(MailStyle.accent).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(MailStyle.paper, lineWidth: 2))
                    }
                }
            VStack(alignment: .leading, spacing: compact ? 4 : MailStyle.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sender).font(.subheadline.weight(isRead ? .medium : .semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .foregroundStyle(MailStyle.ink)
                    Spacer(minLength: 8)
                    if !typeSize.isAccessibilitySize { MailRowDate(date: date).fixedSize() }
                }
                Text(subject.isEmpty ? "No subject" : subject)
                    .font(.body.weight(isRead ? .regular : .medium)).foregroundStyle(MailStyle.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                if previewLines > 0 {
                    Text(preview).font(.subheadline).foregroundStyle(MailStyle.secondaryInk)
                        .lineSpacing(2)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : compact ? min(previewLines, 1) : previewLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if typeSize.isAccessibilitySize || messageCount > 1 || starred || hasAttachments || pinned || account != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { metadata }
                        VStack(alignment: .leading, spacing: 6) { metadata }
                    }.font(.caption).foregroundStyle(MailStyle.secondaryInk)
                }
            }
        }
        .padding(.vertical, compact ? 6 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRead ? "Read" : "Unread")
    }

    @ViewBuilder private var metadata: some View {
        if typeSize.isAccessibilitySize { MailRowDate(date: date) }
        if messageCount > 1 { Text(messageCount, format: .number).monospacedDigit().accessibilityLabel("\(messageCount) messages") }
        if starred { Image(systemName: "star.fill").accessibilityLabel("Starred") }
        if hasAttachments { Image(systemName: "paperclip").accessibilityLabel("Has attachments") }
        if pinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned on this device") }
        if let account {
            Circle().fill(Color(mailHex: account.colourHex)).frame(width: 6, height: 6)
                .accessibilityLabel("Account: \(account.displayName)")
        }
    }
}
