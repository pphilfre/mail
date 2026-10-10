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
    @Query(filter: #Predicate<OutgoingMessage> { $0.stateRaw == "sendUnconfirmed" }) private var uncertain: [OutgoingMessage]
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
    @State private var showingTasks = false
    @State private var showingReceipts = false
    @State private var showingAttachments = false
    @State private var showingPeople = false
    @State private var showingCollections = false
    @State private var showingSubscriptions = false
    @State private var quickFilter = InboxQuickFilter.all
    @State private var sheetDestination: SheetDestination?
    private enum SheetDestination { case accounts, settings, tasks, receipts, attachments, people, collections, subscriptions }
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
        labelFilter.flatMap { id in folders.first { $0.remoteID == id && $0.accountID == accountFilter }?.name } ?? mailbox
    }
    private var scopeTitle: String {
        accounts.first { $0.id == accountFilter }?.email ?? (accounts.isEmpty ? "Sample inbox" : "All accounts")
    }

    var body: some View {
        mailList
        // Recreate the list's size cache when reading density changes, rather than keeping old cell heights.
        .id("mail-density-\(compactInbox)-\(previewLines)")
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MailStyle.paper)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, compactInbox ? 44 : 48)
        .environment(\.editMode, .constant(selecting ? .active : .inactive))
        .safeAreaInset(edge: .bottom) {
            if selecting { bulkToolbar }
            else { composeDock }
        }
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
                Text(mailboxTitle).font(.headline).lineLimit(1).accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Mailboxes", systemImage: "line.3.horizontal") { toggleDrawer() }
                    .accessibilityIdentifier("mailboxDrawerButton")
            }
            ToolbarItem(placement: .primaryAction) {
                profileMenu
            }
        }
        .sheet(isPresented: $showingDrawer, onDismiss: presentDestination) {
            MailboxSheet(accounts: accounts, folders: folders,
                counts: Dictionary(uniqueKeysWithValues: mailboxes.map { name in
                    (name, name == "Drafts" ? draftCount : accounts.isEmpty && showSamples ? sampleUnread(name) : cachedUnread(accountID: accountFilter, mailbox: name))
                }), accountCounts: accountUnreadCounts, labelCounts: labelUnreadCounts,
                account: $accountFilterRaw, mailbox: $mailbox, label: $labelFilter,
                openAccounts: { sheetDestination = .accounts; showingDrawer = false },
                openSettings: { sheetDestination = .settings; showingDrawer = false },
                openTasks: { sheetDestination = .tasks; showingDrawer = false },
                openReceipts: { sheetDestination = .receipts; showingDrawer = false },
                openAttachments: { sheetDestination = .attachments; showingDrawer = false },
                openPeople: { sheetDestination = .people; showingDrawer = false },
                openCollections: { sheetDestination = .collections; showingDrawer = false },
                openSubscriptions: { sheetDestination = .subscriptions; showingDrawer = false })
        }
        .sheet(isPresented: $showingAccounts) {
            NavigationStack { AccountsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAccounts = false } } } }
                .modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } } }
                .modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingSearch) {
            NavigationStack { LocalSearchView(initialAccountID: accountFilter) }
        }
        .sheet(isPresented: $showingCompose) {
            NavigationStack { ComposeView(draft: LocalDraft(accountID: accountFilter)) }
        }
        .sheet(item: $editingDraft) { draft in
            NavigationStack { ComposeView(draft: draft) }
        }
        .sheet(isPresented: $showingTasks) {
            NavigationStack {
                MailTasksView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingTasks = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingReceipts) {
            NavigationStack {
                ReceiptsView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingReceipts = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingAttachments) {
            NavigationStack {
                AttachmentLibraryView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAttachments = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingPeople) {
            NavigationStack {
                PeopleView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPeople = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingCollections) {
            NavigationStack {
                CollectionsView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingCollections = false } } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .sheet(isPresented: $showingSubscriptions) {
            NavigationStack {
                SubscriptionsView(accountID: accountFilter)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingSubscriptions = false }.accessibilityIdentifier("closeSubscriptionsButton")
                    } }
            }.modifier(MailFeedbackOverlay(playsHaptics: false))
        }
        .onChange(of: mailbox) { _, _ in quickFilter = .all; loadMailbox() }
        .task {
            if !mailboxes.contains(mailbox) { mailbox = "Inbox" }
            if let selected = accountFilter, !accounts.contains(where: { $0.id == selected }) { accountFilterRaw = "" }
            loadMailbox()
        }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selected = accountFilter, !ids.contains(selected) { accountFilterRaw = "" }
        }
        .onChange(of: accountFilter) { _, _ in labelFilter = nil; quickFilter = .all; loadMailbox() }
        .onChange(of: labelFilter) { _, _ in quickFilter = .all; loadMailbox() }
        .onChange(of: quickFilter) { _, _ in selectedIDs.removeAll() }
        .onChange(of: conversationRows) { _, _ in selectedIDs.removeAll() }
        .refreshable {
            refreshing = true
            defer { refreshing = false }
            await runtime.gmail?.syncAll()
            if !accounts.isEmpty && (mailbox != "Snoozed" || labelFilter != nil) { await runtime.gmail?.loadMailbox(mailbox, accountID: accountFilter, labelID: labelFilter) }
        }
    }
    private var mailList: some View {
        return List(selection: $selectedIDs) {
            inboxHeader
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(MailStyle.paper)
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
            if !accounts.isEmpty && mailbox == "Inbox" && labelFilter == nil {
                Section {
                    NavigationLink { LocalMailOverview(accountID: accountFilter, catchUp: true) } label: { Label("Catch up", systemImage: "text.badge.star") }
                    NavigationLink { LocalMailOverview(accountID: accountFilter, catchUp: false) } label: { Label("Local categories", systemImage: "tray.2") }
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
            if failedCount > 0 {
                NavigationLink { PendingActionsView(accountID: accountFilter) } label: {
                    Label("\(failedCount) mailbox changes need attention", systemImage: "arrow.triangle.2.circlepath").font(.subheadline)
                }
            }
            if mailbox == "Drafts" && labelFilter == nil {
                DraftSections(accountID: accountFilter, onEdit: { editingDraft = $0 })
            } else if !accounts.isEmpty {
                cachedMailSection
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
        let saved = organisation
        let files = attachmentMessageIDs
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        return Group {

                Section {
                    ForEach(conversations) { conversation in
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
                    if conversations.isEmpty {
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
                ForEach(selectedAccounts.filter { (mailbox != "Snoozed" || labelFilter != nil) && runtime.gmail?.hasOlder($0.id, mailbox: mailbox, labelID: labelFilter) == true }) { account in
                    Button(selectedAccounts.count == 1 ? "Load older messages" : "Load older · \(account.email)") {
                        Task { await runtime.gmail?.loadOlder(account.id, mailbox: mailbox, labelID: labelFilter) }
                    }
                        .disabled(runtime.gmail?.syncing.contains(account.id) == true)
                }
                if !filtered.isEmpty && selectedAccounts.contains(where: { runtime.gmail?.syncing.contains($0.id) == true }) {
                    HStack { ProgressView(); Text("Updating mail…").foregroundStyle(.secondary) }.font(.caption)
                }
        }
    }
    private var inboxHeader: some View {
        InboxHeader(
            filter: $quickFilter, showFilters: mailbox != "Drafts", allowStarred: !accounts.isEmpty,
            canSelect: !accounts.isEmpty && mailbox != "Drafts", selecting: selecting,
            search: { feedback.select(); showingSearch = true },
            select: {
                feedback.select()
                withAnimation(MailStyle.motion(reduced: reduceMotion)) { selecting.toggle(); selectedIDs.removeAll() }
            })
    }
    private var profileMenu: some View {
        Button { toggleDrawer()        } label: {
            Group {
                if let account = accounts.first(where: { $0.id == accountFilter }) { AccountBadge(account: account) }
                else { Image(systemName: "person.crop.circle").font(.system(size: 21, weight: .regular)) }
            }.frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Mail and tools")
        .accessibilityIdentifier("profileMenuButton")
    }
    private var composeDock: some View {
        HStack(alignment: .center) {
            HStack(spacing: 0) {
                Button { feedback.select(); showingDrawer = true } label: {
                    Label("Emails", systemImage: "envelope").frame(height: 56).padding(.horizontal, 14).contentShape(.rect)
                }.accessibilityIdentifier("dockEmailsButton")
                Divider().frame(height: 18)
                Button { feedback.select(); showingTasks = true } label: {
                    Label("Tasks \(openTaskCount)", systemImage: "checklist").frame(height: 56).padding(.horizontal, 14).contentShape(.rect)
                }.accessibilityIdentifier("dockTasksButton")
            }.font(.subheadline.weight(.medium)).buttonStyle(.plain)
                .glassEffect(.regular, in: .capsule)
            Spacer(minLength: 12)
            Button {
                feedback.select(); showingCompose = true
            } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 22, weight: .medium))
                    .frame(width: 56, height: 56).contentShape(.circle)
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            .glassEffect(.regular.tint(MailStyle.accent).interactive(), in: .circle)
            .accessibilityLabel("Compose").accessibilityIdentifier("composeButton")
        }
        .overlay(alignment: .topLeading) {
            if refreshing || selectedAccounts.contains(where: { runtime.gmail?.syncing.contains($0.id) == true }) {
                ProgressView().frame(width: 32, height: 32).glassEffect(.regular, in: .circle)
                    .offset(y: -40).accessibilityLabel("Updating mail").accessibilityIdentifier("mailSyncSpinner")
            } else if let deadline = waitingUntil {
                GmailWaitStatus(deadline: deadline).font(.caption).padding(8).glassEffect(.regular, in: .capsule).offset(y: -40)
            }
        }
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 8)
    }
    private func presentDestination() {
        switch sheetDestination {
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
        feedback.select(); showingDrawer.toggle()
    }
    private func loadMailbox() {
        selecting = false; selectedIDs.removeAll()
        // The unified drafts section owns its initial load and provider-link refresh.
        guard mailbox != "Drafts" || labelFilter != nil else { return }
        guard mailbox != "Snoozed" || labelFilter != nil else { return }
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
            account: accounts[conversation.latest.accountID],
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
        HStack(alignment: .top, spacing: 12) {
            SenderAvatar(email: message.senderEmail, name: message.sender.displayName, size: compactInbox ? 36 : 38)
                .overlay(alignment: .bottomTrailing) {
                    if !isRead { Circle().fill(MailStyle.accent).frame(width: 9, height: 9).overlay(Circle().stroke(.background, lineWidth: 2)) }
                }
            VStack(alignment: .leading, spacing: compactInbox ? 2 : MailStyle.rowSpacing) {
                HStack {
                    Text(message.sender.displayName).font(.system(.subheadline, weight: isRead ? .medium : .semibold)).lineLimit(1)
                    if messageCount > 1 {
                        Text(messageCount, format: .number).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(MailStyle.canvas, in: .capsule)
                            .accessibilityLabel("\(messageCount) messages")
                    }
                    Spacer()
                    if starred ?? message.isStarred { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                    if hasAttachments { Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Has attachments") }
                    MailRowDate(date: message.receivedAt)
                }
                Text(message.subject.isEmpty ? "No subject" : message.subject).font(.subheadline.weight(isRead ? .regular : .medium)).lineLimit(1)
                if previewLines > 0 { Text(message.snippet).font(compactInbox ? .caption : .subheadline).foregroundStyle(.secondary).lineLimit(compactInbox ? min(previewLines, 1) : previewLines).fixedSize(horizontal: false, vertical: true) }
                if let account {
                    HStack(spacing: 4) {
                        Circle().fill(Color(mailHex: account.colourHex)).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text(account.displayName).lineLimit(1)
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, compactInbox ? 3 : 8)
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color(mailHex: account?.colourHex ?? "007AFF"))
                .frame(width: 3).padding(.vertical, 4).accessibilityHidden(true)
        }
        .overlay(alignment: .bottomTrailing) {
            if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("Pinned on this device") }
        }
        .accessibilityElement(children: .combine).accessibilityValue(isRead ? "Read" : "Unread")
    }
}

struct MessageRow: View {
    let message: SampleMessage
    @AppStorage("previewLines") private var previewLines = 2
    @AppStorage("compactInbox") private var compactInbox = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SenderAvatar(email: message.address, name: message.sender, allowsRemoteIcon: false, size: compactInbox ? 36 : 38)
                .overlay(alignment: .bottomTrailing) {
                    if !message.isRead {
                        Circle().fill(MailStyle.accent).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(MailStyle.paper, lineWidth: 2))
                    }
                }
            VStack(alignment: .leading, spacing: compactInbox ? 2 : MailStyle.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.sender).font(.system(.subheadline, weight: message.isRead ? .medium : .semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    MailRowDate(date: message.date)
                }
                Text(message.subject).font(.subheadline.weight(message.isRead ? .regular : .medium)).lineLimit(1)
                if previewLines > 0 { Text(message.snippet).font(compactInbox ? .caption : .subheadline).foregroundStyle(.secondary).lineLimit(compactInbox ? min(previewLines, 1) : previewLines).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .padding(.vertical, compactInbox ? 3 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityValue(message.isRead ? "Read" : "Unread")
    }
}
