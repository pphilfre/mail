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
                isRead: message.isRead, isStarred: message.isStarred, hasAttachments: !filenames.isEmpty)
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
                          initialAccountID: initialAccountID)
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
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    let index: MailSearchIndex
    let indexing: Bool
    let mailByID: [UUID: MailMessage]
    let accounts: [MailAccount]
    let samplesByID: [UUID: SampleMessage]
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
         samplesByID: [UUID: SampleMessage], initialAccountID: UUID?) {
        self.index = index; self.indexing = indexing; self.mailByID = mailByID
        self.accounts = accounts; self.samplesByID = samplesByID
        _accountID = State(initialValue: initialAccountID)
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = MailSearchQuery(query)
        let ids = index.matches(query, accountID: accountID, includeTrashAndSpam: includeTrashAndSpam, filters: filters)
        List {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterChip("Unread", value: $filters.unread)
                    filterChip("Starred", value: $filters.starred)
                    Menu {
                        Button("Any sender") { filters.sender = nil }
                        Button("Enter sender…") { senderText = filters.sender ?? ""; showingSenderFilter = true }
                        ForEach(Array(Set(mailByID.values.map(\.senderEmail))).sorted().prefix(30), id: \.self) { email in
                            Button(email) { filters.sender = email }
                        }
                    } label: { Label(filters.sender ?? "Sender", systemImage: "person").lineLimit(1).frame(minHeight: 44) }
                    Menu {
                        Button("Any date") { filters.after = nil; filters.before = nil }
                        Button("Last 7 days") { filters.after = Calendar.current.date(byAdding: .day, value: -7, to: Date()); filters.before = nil }
                        Button("Last 30 days") { filters.after = Calendar.current.date(byAdding: .day, value: -30, to: Date()); filters.before = nil }
                        Button("Date range…") { showingDateFilters = true }
                    } label: { Label(filters.after != nil || filters.before != nil ? "Date filtered" : "Date", systemImage: "calendar").frame(minHeight: 44) }
                    Menu {
                        Button("Any attachments") { filters.attachments = false; filters.attachmentPresence = nil }
                        Button("With attachments") { filters.attachments = false; filters.attachmentPresence = true }
                        Button("Without attachments") { filters.attachments = false; filters.attachmentPresence = false }
                    } label: { Label(filters.attachmentPresence == true ? "With files" : filters.attachmentPresence == false ? "Without files" : "Attachments", systemImage: "paperclip").frame(minHeight: 44) }
                    Menu {
                        Button("All accounts") { accountID = nil }
                        ForEach(accounts) { account in Button(account.email) { accountID = account.id } }
                    } label: { Label(accounts.first { $0.id == accountID }?.email ?? "Account", systemImage: "person.crop.circle").frame(minHeight: 44) }
                    if filters.active { Button("Reset") { filters = MailSearchFilters(); accountID = nil }.font(.caption) }
                }.padding(.vertical, 4)
            }.listRowSeparator(.hidden)
            if indexing {
                HStack { ProgressView(); Text("Preparing search…").foregroundStyle(.secondary) }
            } else if let error = parsed.error {
                Label(error, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            } else if trimmed.isEmpty && !filters.active && accountID == nil {
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
                        .disabled((!parsed.active && !filters.active && accountID == nil) || parsed.error != nil || savedSearches.count >= 20)
                    Button("Clear search") { query = ""; filters = MailSearchFilters() }
                }
            }
        }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selected = accountID, !ids.contains(selected) { accountID = nil }
        }
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
