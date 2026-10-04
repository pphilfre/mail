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
                                      isTrash: message.isTrash, isSpam: message.isSpam)
        } + samples.map {
            MailSearchDocument(id: $0.id, accountID: nil, fields: [$0.sender, $0.address, $0.subject, $0.snippet])
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

    init(index: MailSearchIndex, indexing: Bool, mailByID: [UUID: MailMessage], accounts: [MailAccount],
         samplesByID: [UUID: SampleMessage], initialAccountID: UUID?) {
        self.index = index; self.indexing = indexing; self.mailByID = mailByID
        self.accounts = accounts; self.samplesByID = samplesByID
        _accountID = State(initialValue: initialAccountID)
    }

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = index.matches(query, accountID: accountID, includeTrashAndSpam: includeTrashAndSpam)
        List {
            if accounts.count > 1 {
                Picker("Account", selection: $accountID) {
                    Text("All accounts").tag(UUID?.none)
                    ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
                }
            }
            if indexing {
                HStack { ProgressView(); Text("Preparing search…").foregroundStyle(.secondary) }
            } else if trimmed.isEmpty {
                ContentUnavailableView("Search your mail", systemImage: "magnifyingglass",
                    description: Text("Find people, subjects, labels, or attachment names in mail saved on this device."))
                    .listRowBackground(Color.clear)
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
        .accessibilityIdentifier("searchResultsList")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $searchPresented,
                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Search cached mail")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarLeading) {
                Menu("Search options", systemImage: "line.3.horizontal.decrease") {
                    Toggle("Include Trash and Spam", isOn: $includeTrashAndSpam)
                }
            }
        }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selected = accountID, !ids.contains(selected) { accountID = nil }
        }
    }
}
