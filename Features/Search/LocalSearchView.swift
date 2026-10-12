import SwiftUI
import SwiftData

/// This parent observes cache changes; query text lives in the child so keystrokes do not rebuild snapshots.
struct LocalSearchView: View {
    var dismissible = true
    @Environment(AppSession.self) private var session
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @Query private var folders: [MailFolder]
    @Query private var attachments: [MailAttachment]
    @AppStorage("showSampleInbox") private var showSamples = false
    @State private var index = MailSearchIndex()
    @State private var indexing = true
    let initialAccountID: UUID?
    var onClose: (() -> Void)? = nil
    init(initialAccountID: UUID?, dismissible: Bool = true, onClose: (() -> Void)? = nil) {
        self.initialAccountID = initialAccountID; self.dismissible = dismissible; self.onClose = onClose
    }

    private var samples: [SampleMessage] { accounts.isEmpty && showSamples ? session.sampleMessages : [] }
    private var documents: [MailSearchDocument] {
        let accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, [$0.email, $0.displayName]) })
        let accountFolders = Dictionary(grouping: folders, by: \.accountID)
        let messageAttachments = Dictionary(grouping: attachments, by: \.messageID)
        return messages.map { message in
            let addresses = ([message.sender] + message.to + message.cc + message.bcc).flatMap { [$0.displayName, $0.email] }
            let labelNames = (accountFolders[message.accountID] ?? []).filter { message.folderIDs.contains($0.remoteID) }.map(\.name)
            let filenames = (messageAttachments[message.id] ?? []).map(\.filename)
            let fields = addresses + [message.subject, message.snippet] + (accountNames[message.accountID] ?? []) + labelNames + filenames
            return MailSearchDocument(id: message.id, accountID: message.accountID, fields: fields,
                isTrash: message.isTrash, isSpam: message.isSpam,
                sender: "\(message.sender.displayName) \(message.senderEmail)",
                recipients: (message.to + message.cc + message.bcc).flatMap { [$0.displayName, $0.email] },
                subject: message.subject, labels: labelNames + message.folderIDs, receivedAt: message.receivedAt,
                isRead: message.isRead, isStarred: message.isStarred, hasAttachments: !filenames.isEmpty,
                semanticText: String(message.snippet.prefix(1_000)))
        } + samples.map {
            MailSearchDocument(id: $0.id, accountID: nil, fields: [$0.sender, $0.address, $0.subject, $0.snippet],
                sender: "\($0.sender) \($0.address)", subject: $0.subject, receivedAt: $0.date, isRead: $0.isRead)
        }
    }

    var body: some View {
        let snapshot = documents
        SearchResultsView(index: index, indexing: indexing,
                          mailByID: Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) }),
                          accounts: accounts, samplesByID: Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) }),
                          initialAccountID: initialAccountID, documents: snapshot, dismissible: dismissible, onClose: onClose)
            .task(id: snapshot) {
                indexing = true
                let work = Task.detached(priority: .userInitiated) { MailSearchIndex(documents: snapshot) }
                let updated = await withTaskCancellationHandler {
                    await work.value
                } onCancel: {
                    work.cancel()
                }
                guard !Task.isCancelled else { return }
                index = updated
                indexing = false
            }
    }
}

private struct SearchResultsView: View {
    private struct SemanticRequest: Equatable {
        let query: String
        let accountID: UUID?
        let includeTrashAndSpam: Bool
        let filters: MailSearchFilters
        let documents: [MailSearchDocument]
        let enabled: Bool
        let indexing: Bool
    }
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    let index: MailSearchIndex
    let indexing: Bool
    let mailByID: [UUID: MailMessage]
    let accounts: [MailAccount]
    let samplesByID: [UUID: SampleMessage]
    let documents: [MailSearchDocument]
    let dismissible: Bool
    let onClose: (() -> Void)?
    let initialAccountID: UUID?
    @State private var semanticEngine = MailSemanticSearch()
    @State private var semanticIDs: [UUID]?
    @State private var resultIDs: [UUID] = []
    @State private var completedRequest: SemanticRequest?
    @AppStorage("semanticMailSearch") private var meaning = false
    @State private var query = ""
    @State private var searchPresented = false
    @FocusState private var searchFocused: Bool
    @State private var accountID: UUID?
    @State private var includeTrashAndSpam = false
    @State private var filters = MailSearchFilters()
    @AppStorage("recentMailSearches") private var recentRaw = "[]"
    @AppStorage("keepSearchHistory") private var keepHistory = true
    @AppStorage("savedMailSearches") private var savedRaw = "[]"
    @State private var namingSearch = false
    @State private var searchName = ""
    @State private var showingDateFilters = false
    @State private var showingSenderFilter = false
    @State private var senderText = ""
    private var savedSearches: [SavedMailSearch] {
        SavedMailSearch.decode(savedRaw).filter { search in
            search.accountID == nil || accounts.contains { $0.id == search.accountID }
        }
    }
    private var recent: [String] { (try? JSONDecoder().decode([String].self, from: Data(recentRaw.utf8))) ?? [] }

    init(index: MailSearchIndex, indexing: Bool, mailByID: [UUID: MailMessage], accounts: [MailAccount],
         samplesByID: [UUID: SampleMessage], initialAccountID: UUID?, documents: [MailSearchDocument], dismissible: Bool, onClose: (() -> Void)?) {
        self.index = index; self.indexing = indexing; self.mailByID = mailByID
        self.accounts = accounts; self.samplesByID = samplesByID
        _accountID = State(initialValue: initialAccountID)
        self.documents = documents
        self.dismissible = dismissible
        self.onClose = onClose
        self.initialAccountID = initialAccountID
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = MailSearchQuery(query)
        let request = SemanticRequest(query: query, accountID: accountID, includeTrashAndSpam: includeTrashAndSpam,
                                      filters: filters, documents: documents, enabled: meaning, indexing: indexing)
        let ready = completedRequest == request
        let ids = ready ? resultIDs : []
        List {
            if accounts.count > 1 {
                Picker("Account", selection: $accountID) {
                    Text("All accounts").tag(UUID?.none)
                    ForEach(accounts) { Text($0.displayName).tag(Optional($0.id)) }
                }.listRowSeparator(.hidden)
            }
            if filters.active || accountID != nil || includeTrashAndSpam || meaning {
                HStack {
                    Text(meaning ? "By meaning" : "Filtered mail").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { filters = MailSearchFilters(); accountID = nil; includeTrashAndSpam = false; meaning = false }
                        .font(.caption)
                }.listRowSeparator(.hidden)
            }
            if meaning && ready && semanticIDs == nil && !trimmed.isEmpty {
                Text("Meaning search unavailable for this language. Showing keyword matches.").font(.caption).foregroundStyle(.secondary)
            }
            if indexing || !ready {
                HStack { ProgressView(); Text("Preparing search…").foregroundStyle(.secondary) }
            } else if let error = parsed.error {
                Label(error, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            } else if trimmed.isEmpty && !filters.active && accountID == nil {
                if !savedSearches.isEmpty {
                    Section("Saved searches") {
                        ForEach(savedSearches) { search in
                            Button {
                                query = search.query; accountID = search.accountID
                                filters = search.filters; includeTrashAndSpam = search.includeTrashAndSpam
                            } label: {
                                Label(search.name, systemImage: "line.3.horizontal.decrease.circle")
                            }.contextMenu {
                                Button("Delete saved search", role: .destructive) {
                                    savedRaw = SavedMailSearch.encode(SavedMailSearch.decode(savedRaw).filter { $0.id != search.id })
                                }
                            }
                        }
                    }
                }
                if keepHistory && !recent.isEmpty {
                    Section("Recent searches") {
                        ForEach(recent, id: \.self) { value in
                            Button(value, systemImage: "clock") { query = value }
                        }
                        Button("Clear recent searches") { recentRaw = "[]" }
                    }
                }
                Section("Suggestions") {
                    ForEach(Array(Set(mailByID.values.map(\.senderEmail))).sorted().prefix(5), id: \.self) { email in
                        Button(email, systemImage: "person.crop.circle") { query = "from:" + email }
                    }
                    Button("Mail with attachments", systemImage: "paperclip") { filters.attachmentPresence = true }
                    Button("Unread mail", systemImage: "envelope.badge") { filters.unread = true }
                }
            } else if ids.isEmpty {
                ContentUnavailableView.search(text: trimmed)
                    .accessibilityIdentifier("searchNoResults")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(ids, id: \.self) { id in
                        if let message = mailByID[id] {
                            NavigationLink { GmailMessageView(message: message) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    CachedMessageRow(message: message)
                                    if accountID == nil && accounts.count > 1,
                                       let account = accounts.first(where: { $0.id == message.accountID }) {
                                        Text(account.email).font(.caption).foregroundStyle(.secondary).padding(.leading, 52)
                                    }
                                }
                            }.accessibilityIdentifier("searchResultMail-\(id.uuidString)")
                        } else if let sample = samplesByID[id] {
                            NavigationLink { MessageView(message: sample) } label: { MessageRow(message: sample) }
                                .accessibilityIdentifier("searchResultSample-\(sample.address)")
                        }
                    }
                } header: {
                    Text("\(ids.count) \(ids.count == 1 ? "result" : "results")")
                } footer: {
                    Text("Searching mail saved on this device\(includeTrashAndSpam ? ", including Trash and Spam" : "").")
                }
            }
        }
        .listStyle(.plain)
        .listRowBackground(MailStyle.paper)
        .scrollContentBackground(.hidden)
        .background(MailStyle.paper)
        .safeAreaInset(edge: .top, spacing: 0) { filterBar.background(MailStyle.paper) }
        .accessibilityIdentifier("searchResultsList")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) {
            guard !indexing else { return }
            do {
                if !trimmed.isEmpty && completedRequest?.query != request.query { try await Task.sleep(for: .milliseconds(180)) }
                let snapshot = index
                let work = Task.detached(priority: .userInitiated) {
                    snapshot.matches(request.query, accountID: request.accountID,
                        includeTrashAndSpam: request.includeTrashAndSpam, filters: request.filters)
                }
                let lexical = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                let matches = meaning ? try await semanticEngine.search(query, documents: documents, accountID: accountID,
                    includeTrashAndSpam: includeTrashAndSpam, filters: filters) : nil
                try Task.checkCancellation()
                semanticIDs = matches; resultIDs = matches ?? lexical; completedRequest = request
            } catch { }
        }
        .searchable(text: $query, isPresented: $searchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Search mail")
        .searchFocused($searchFocused)
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .task { await Task.yield(); searchPresented = true; searchFocused = true }
        .onSubmit(of: .search) { rememberQuery() }
        .onDisappear { rememberQuery() }
        .toolbar {
            if dismissible { ToolbarItem(placement: .confirmationAction) {
                Button("Close") { onClose?(); dismiss() }.accessibilityIdentifier("closeSearchButton")
            } }
            ToolbarItem(placement: .topBarLeading) {
                Menu("Search history", systemImage: "ellipsis") {
                    Toggle("Keep recent searches", isOn: $keepHistory)
                    Button("Save this search") { searchName = ""; namingSearch = true }
                        .disabled((!parsed.active && !filters.active && accountID == nil) || parsed.error != nil || savedSearches.count >= 20)
                    Button("Clear search") { query = ""; filters = MailSearchFilters() }
                }
            }
        }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selected = accountID, !ids.contains(selected) { accountID = nil }
        }
        .onChange(of: initialAccountID) { _, value in accountID = value }
        .onChange(of: keepHistory) { _, enabled in if !enabled { recentRaw = "[]" } }
        .alert("Sender", isPresented: $showingSenderFilter) {
            TextField("Name or email", text: $senderText).textInputAutocapitalization(.never)
            Button("Apply") { filters.sender = senderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : senderText.trimmingCharacters(in: .whitespacesAndNewlines) }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingDateFilters) {
            NavigationStack {
                Form {
                    Toggle("From date", isOn: Binding(get: { filters.after != nil }, set: { filters.after = $0 ? Calendar.current.startOfDay(for: Date()) : nil }))
                    if filters.after != nil { DatePicker("From (inclusive)", selection: Binding(get: { filters.after ?? Date() }, set: { filters.after = Calendar.current.startOfDay(for: $0) }), displayedComponents: .date) }
                    Toggle("Before date", isOn: Binding(get: { filters.before != nil }, set: { filters.before = $0 ? Calendar.current.startOfDay(for: Date()) : nil }))
                    if filters.before != nil { DatePicker("Before (exclusive)", selection: Binding(get: { filters.before ?? Date() }, set: { filters.before = Calendar.current.startOfDay(for: $0) }), displayedComponents: .date) }
                }.navigationTitle("Date range")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDateFilters = false } } }
            }.presentationDetents([.medium])
        }
        .alert("Save search", isPresented: $namingSearch) {
            TextField("Name", text: $searchName)
            Button("Save") { saveSearch() }
                .disabled(searchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { }
        } message: { Text("Reuses this query, filters and account. Results cover downloaded mail.") }
    }
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                Button("All") { filters = MailSearchFilters(); accountID = nil; includeTrashAndSpam = false; meaning = false }
                    .foregroundStyle(!filters.active && !meaning && !includeTrashAndSpam && accountID == nil ? MailStyle.accent : .secondary)
                filterChip("Unread", value: $filters.unread)
                filterChip("Starred", value: $filters.starred)
                filterChip("Attachments", value: Binding(get: { filters.attachmentPresence == true }, set: { filters.attachments = false; filters.attachmentPresence = $0 ? true : nil }))
                filterChip("No attachments", value: Binding(get: { filters.attachmentPresence == false }, set: { filters.attachments = false; filters.attachmentPresence = $0 ? false : nil }))
                Button(filters.sender ?? "Sender") { senderText = filters.sender ?? ""; showingSenderFilter = true }
                    .foregroundStyle(filters.sender != nil ? MailStyle.accent : .secondary)
                Button("Date") { showingDateFilters = true }
                    .foregroundStyle(filters.after != nil || filters.before != nil ? MailStyle.accent : .secondary)
                filterChip("By meaning", value: $meaning)
                filterChip("Trash & Spam", value: $includeTrashAndSpam)
            }.font(.subheadline.weight(.medium)).buttonStyle(.plain).padding(.horizontal, 16).frame(minHeight: 44)
        }.accessibilityIdentifier("searchFilterBar")
    }
    private func filterChip(_ title: String, value: Binding<Bool>) -> some View {
        Button { feedback.select(); value.wrappedValue.toggle() } label: {
            HStack(spacing: 4) {
                if value.wrappedValue { Image(systemName: "checkmark") }
                Text(title)
            }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                .foregroundStyle(value.wrappedValue ? MailStyle.accent : .secondary)
        }.buttonStyle(.plain).accessibilityAddTraits(value.wrappedValue ? [.isSelected] : [])
    }
    private func rememberQuery() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keepHistory, !value.isEmpty, MailSearchQuery(value).error == nil else { return }
        let values = Array(([value] + recent.filter { $0 != value }).prefix(10))
        if let data = try? JSONEncoder().encode(values) { recentRaw = String(decoding: data, as: UTF8.self) }
    }
    private func saveSearch() {
        let name = searchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, savedSearches.count < 20, MailSearchQuery(query).error == nil else { return }
        let search = SavedMailSearch(name: name, query: query, accountID: accountID,
            includeTrashAndSpam: includeTrashAndSpam, filters: filters)
        savedRaw = SavedMailSearch.encode(savedSearches + [search])
    }
}
