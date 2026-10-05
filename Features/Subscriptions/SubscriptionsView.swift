import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    let accountID: UUID?
    @Query private var messages: [MailMessage]
    @Query private var metadata: [StoreMetadata]
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppSession.self) private var session
    @Environment(MailFeedback.self) private var feedback
    @State private var query = ""
    @State private var unreadOnly = false
    @State private var managing = false
    @State private var archiving: SubscriptionEntry?
    @State private var errorMessage: String?
    private var entries: [SubscriptionEntry] {
        let rules = metadata.filter { $0.key.hasPrefix("subscription-rule:") }.compactMap { try? SubscriptionRule.decode($0) }
        return SubscriptionInsights.entries(messages, rules: rules, accountID: accountID).filter {
            (!unreadOnly || $0.unreadCount > 0) && (query.isEmpty || $0.email.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        List {
            Section {
                Toggle("Unread only", isOn: $unreadOnly)
                Text("Likely newsletters from downloaded mail. Counts cover this device; frequency is the last 7 days.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Manage newsletter senders", systemImage: "slider.horizontal.3") { managing = true }
                    .accessibilityIdentifier("manageSubscriptionsButton")
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink { SenderProfileView(email: entry.email, name: entry.name, initialAccountID: accountID) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            SenderAvatar(email: entry.email, name: entry.name)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.name).font(.headline)
                                Text(entry.email).font(.caption).foregroundStyle(.secondary)
                                Text("\(entry.unreadCount) unread · \(entry.messages.count) \(entry.messages.count == 1 ? "message" : "messages") · \(entry.weeklyCount) in 7 days")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(entry.manuallyIncluded ? "Added by you" : "Suggested newsletter").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let latest = entry.messages.first { Text("Latest: \(latest.receivedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button("Archive downloaded inbox mail", systemImage: "archivebox") { archiving = entry }
                            .disabled(!entry.messages.contains(where: { $0.isInbox }))
                            .accessibilityIdentifier("archiveSubscription-\(entry.email)")
                        Spacer()
                        Button("Exclude", systemImage: "minus.circle") { set(entry, included: false) }.labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Exclude \(entry.email) from subscriptions")
                    }.font(.caption)
                }.padding(.vertical, 8).buttonStyle(.borderless).accessibilityIdentifier("subscription-\(entry.email)")
            }
            if entries.isEmpty {
                ContentUnavailableView("No newsletters here", systemImage: "newspaper",
                    description: Text("Try another filter or add a sender through Manage newsletter senders."))
            }
            if metadata.contains(where: { $0.key.hasPrefix("subscription-rule:") && (try? SubscriptionRule.decode($0)) == nil }) {
                Text(SubscriptionRuleError.invalidData.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Subscriptions").searchable(text: $query, prompt: "Newsletter sender")
        .sheet(isPresented: $managing) { NavigationStack { SubscriptionSenderManager(accountID: accountID) } }
        .confirmationDialog("Archive downloaded newsletter mail?", isPresented: Binding(
            get: { archiving != nil }, set: { if !$0 { archiving = nil } }), titleVisibility: .visible) {
            if let entry = archiving {
                let count = entry.messages.filter { $0.isInbox }.count
                Button("Archive \(count) inbox \(count == 1 ? "message" : "messages")") { archive(entry); archiving = nil }
            }
        } message: { Text("Moves this sender's downloaded inbox messages to Archive. You can undo from the inbox.") }
    }
    private func set(_ entry: SubscriptionEntry, included: Bool) {
        do {
            guard let repository = runtime.repository else { throw GmailError.reconnect }
            try repository.setSubscription(email: entry.email, included: included, accountIDs: Set(entry.messages.map(\.accountID)))
        } catch { errorMessage = error.localizedDescription }
    }
    private func archive(_ entry: SubscriptionEntry) {
        let inbox = entry.messages.filter { $0.isInbox }
        guard !inbox.isEmpty else { return }
        feedback.triageKind = "archive"
        if let gmail = runtime.gmail { gmail.action("archive", messages: inbox) }
        else {
            do { try runtime.repository?.enqueueBatch("archive", messages: inbox) }
            catch { session.storageError = error.localizedDescription }
        }
    }
}

private struct SubscriptionSenderManager: View {
    let accountID: UUID?
    @Query private var messages: [MailMessage]
    @Query private var metadata: [StoreMetadata]
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var errorMessage: String?
    var body: some View {
        let people = SenderInsights.directory(messages, accountID: accountID).filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.email.localizedCaseInsensitiveContains(query)
        }
        let rules = metadata.filter { $0.key.hasPrefix("subscription-rule:") }.compactMap { try? SubscriptionRule.decode($0) }
        let included = Set(SubscriptionInsights.entries(messages, rules: rules, accountID: accountID).map(\.email))
        List {
            Text("Add or exclude a sender, or reset your choice to use newsletter detection. Choices apply to accounts shown here.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(people) { person in
                VStack(alignment: .leading, spacing: 8) {
                    Text(person.name).font(.headline)
                    Text(person.email).font(.caption).foregroundStyle(.secondary)
                    Text(included.contains(person.email) ? "In subscriptions" : "Outside subscriptions").font(.caption)
                    HStack {
                        Button("Include") { set(person.email, included: true) }.accessibilityIdentifier("includeSubscription-\(person.email)")
                        Spacer()
                        Button("Exclude") { set(person.email, included: false) }.accessibilityIdentifier("excludeSubscription-\(person.email)")
                        Spacer()
                        Button("Reset") { set(person.email, included: nil) }
                    }.font(.subheadline).buttonStyle(.borderless)
                }.padding(.vertical, 6)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Newsletter senders").searchable(text: $query, prompt: "Sender name or email")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    private func set(_ email: String, included: Bool?) {
        do {
            guard let repository = runtime.repository else { throw GmailError.reconnect }
            let owners = Set(SenderInsights.received(messages, email: email, accountID: accountID).map(\.accountID))
            try repository.setSubscription(email: email, included: included, accountIDs: owners)
        } catch { errorMessage = error.localizedDescription }
    }
}
