import SwiftUI
import SwiftData

/// This parent observes cache changes; query text lives in the child so keystrokes do not rebuild snapshots.
struct LocalSearchView: View {
    @Environment(AppSession.self) private var session
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @Query private var folders: [MailFolder]
    @Query private var attachments: [MailAttachment]
    @AppStorage("showSampleInbox") private var showSamples = false
    @State private var index = MailSearchIndex()
    @State private var indexing = true
    let initialAccountID: UUID?

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
                semanticText: String((message.plainTextBody ?? message.snippet).prefix(1_000)))
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
                          initialAccountID: initialAccountID, documents: snapshot)
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
    }
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    let index: MailSearchIndex
    let indexing: Bool
    let mailByID: [UUID: MailMessage]
    let accounts: [MailAccount]
    let samplesByID: [UUID: SampleMessage]
    let documents: [MailSearchDocument]
    @State private var semanticEngine = MailSemanticSearch()
    @State private var semanticIDs: [UUID]?
    @State private var completedRequest: SemanticRequest?
    @AppStorage("semanticMailSearch") private var meaning = false
    @State private var query = ""
    @State private var searchPresented = true
    @State private var accountID: UUID?
    @State private var includeTrashAndSpam = false
    @State private var filters = MailSearchFilters()
    @AppStorage("recentMailSearches") private var recentRaw = "[]"
    @AppStorage("keepSearchHistory") private var keepHistory = true
    @AppStorage("savedMailSearches") private var savedRaw = "[]"
    @State private var namingSearch = false
    @State private var searchName = ""
    private var savedSearches: [SavedMailSearch] {
        SavedMailSearch.decode(savedRaw).filter { search in
            search.accountID == nil || accounts.contains { $0.id == search.accountID }
        }
    }
    private var recent: [String] { (try? JSONDecoder().decode([String].self, from: Data(recentRaw.utf8))) ?? [] }

    init(index: MailSearchIndex, indexing: Bool, mailByID: [UUID: MailMessage], accounts: [MailAccount],
         samplesByID: [UUID: SampleMessage], initialAccountID: UUID?, documents: [MailSearchDocument]) {
        self.index = index; self.indexing = indexing; self.mailByID = mailByID
        self.accounts = accounts; self.samplesByID = samplesByID
        _accountID = State(initialValue: initialAccountID)
        self.documents = documents
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = MailSearchQuery(query)
        let request = SemanticRequest(query: query, accountID: accountID, includeTrashAndSpam: includeTrashAndSpam,
                                      filters: filters, documents: documents, enabled: meaning)
        let ready = completedRequest == request
        let lexicalIDs = index.matches(query, accountID: accountID, includeTrashAndSpam: includeTrashAndSpam, filters: filters)
        let ids = meaning && !ready ? [] : meaning ? semanticIDs ?? lexicalIDs : lexicalIDs
        List {
            Picker("Search method", selection: $meaning) {
                Text("Keywords").tag(false); Text("Meaning").tag(true)
            }.pickerStyle(.segmented)
            if meaning {
                Text("Semantic search ranks up to 50 matches from the latest 1,000 cached emails in your scope. Uses Apple sentence embeddings when available for the query’s language.")
                    .font(.caption).foregroundStyle(.secondary)
                if ready && semanticIDs == nil && !trimmed.isEmpty { Text("Sentence embeddings unavailable for this query; showing keyword matches.").font(.caption).foregroundStyle(.secondary) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterChip("Unread", value: $filters.unread)
                    filterChip("Starred", value: $filters.starred)
                    filterChip("Attachments", value: $filters.attachments)
                    if filters.active { Button("Reset") { filters = MailSearchFilters() }.font(.caption) }
                }.padding(.vertical, 4)
            }.listRowSeparator(.hidden)
            if accounts.count > 1 {
                Picker("Account", selection: $accountID) {
                    Text("All accounts").tag(UUID?.none)
                    ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
                }
            }
            if indexing || (meaning && !ready) {
                HStack { ProgressView(); Text("Preparing search…").foregroundStyle(.secondary) }
            } else if let error = parsed.error {
                Label(error, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            } else if trimmed.isEmpty && !filters.active {
                ContentUnavailableView("Search your mail", systemImage: "magnifyingglass",
                    description: Text("Find people, subjects, labels, or attachment names in mail saved on this device."))
                    .listRowBackground(Color.clear)
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
                Section("Search tips") {
                    Text("Try from:alex, subject:\"weekend plans\", label:Work, before:2026-10-01 or has:attachment.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Dates use your local calendar. after: includes the specified day; before: excludes it.")
                        .font(.caption).foregroundStyle(.secondary)
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
        .scrollContentBackground(.hidden)
        .background(MailStyle.paper)
        .accessibilityIdentifier("searchResultsList")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) {
            guard meaning else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                let matches = try await semanticEngine.search(query, documents: documents, accountID: accountID,
                    includeTrashAndSpam: includeTrashAndSpam, filters: filters)
                try Task.checkCancellation()
                semanticIDs = matches; completedRequest = request
            } catch { }
        }
        .searchable(text: $query, isPresented: $searchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Search cached mail")
        .onSubmit(of: .search) { rememberQuery() }
        .onDisappear { rememberQuery() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarLeading) {
                Menu("Search options", systemImage: "line.3.horizontal.decrease") {
                    Toggle("Include Trash and Spam", isOn: $includeTrashAndSpam)
                    Toggle("Keep recent searches", isOn: $keepHistory)
                    Button("Save this search") { searchName = ""; namingSearch = true }
                        .disabled((!parsed.active && !filters.active) || parsed.error != nil || savedSearches.count >= 20)
                    Button("Clear search") { query = ""; filters = MailSearchFilters() }
                }
            }
        }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selected = accountID, !ids.contains(selected) { accountID = nil }
        }
        .onChange(of: keepHistory) { _, enabled in if !enabled { recentRaw = "[]" } }
        .alert("Save search", isPresented: $namingSearch) {
            TextField("Name", text: $searchName)
            Button("Save") { saveSearch() }
                .disabled(searchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { }
        } message: { Text("Reuses this query, filters and account. Results cover downloaded mail.") }
    }
    private func filterChip(_ title: String, value: Binding<Bool>) -> some View {
        Button { feedback.select(); value.wrappedValue.toggle() } label: {
            HStack(spacing: 4) {
                if value.wrappedValue { Image(systemName: "checkmark") }
                Text(title)
            }.font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                .background(value.wrappedValue ? MailStyle.accent.opacity(0.1) : MailStyle.canvas, in: Capsule())
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
