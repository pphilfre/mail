import SwiftUI
import SwiftData

struct OutboxView: View {
    @Environment(AppRuntime.self) private var runtime
    @Query(filter: #Predicate<OutgoingMessage> { $0.stateRaw == "sendUnconfirmed" || $0.stateRaw == "scheduled" || $0.stateRaw == "sendFailed" }, sort: \OutgoingMessage.updatedAt, order: .reverse)
    private var outgoing: [OutgoingMessage]
    @Query private var accounts: [MailAccount]
    @Query private var metadata: [StoreMetadata]
    @Environment(AppSession.self) private var session
    @State private var checking: Set<UUID> = []
    @State private var errors: [UUID: String] = [:]
    let accountID: UUID?
    private var pending: [OutgoingMessage] { outgoing.filter { accountID == nil || $0.accountID == accountID } }

    var body: some View {
        List {
            if pending.isEmpty {
                ContentUnavailableView("Nothing to check", systemImage: "checkmark.circle",
                    description: Text("All send confirmations have been resolved."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    Text("These messages may already have been sent. Check for a sent copy before sending another. Dispatch keeps your copy and never resends it automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(pending) { row in
                    Section {
                        NavigationLink {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(row.subject.isEmpty ? "No subject" : row.subject).font(.title2.bold())
                                    Text("To: " + row.toRaw).font(.callout).foregroundStyle(.secondary)
                                    if !row.ccRaw.isEmpty { Text("Cc: " + row.ccRaw).font(.caption).foregroundStyle(.secondary) }
                                    if !row.bccRaw.isEmpty { Text("Bcc: " + row.bccRaw).font(.caption).foregroundStyle(.secondary) }
                                    Text(row.body).frame(maxWidth: .infinity, alignment: .leading)
                                    SavedOutgoingAttachmentsView(outgoingID: row.id)
                                }.padding().textSelection(.enabled)
                            }.navigationTitle("Saved copy").navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.subject.isEmpty ? "No subject" : row.subject).font(.headline)
                                Text(row.toRaw).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                if let account = accounts.first(where: { $0.id == row.accountID }) {
                                    Text(account.email).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if row.stateRaw != "sendUnconfirmed" {
                            if let saved = metadata.first(where: { $0.key == ScheduledDelivery.key(row.id) }),
                               let delivery = try? JSONDecoder().decode(ScheduledDelivery.self, from: Data(saved.value.utf8)) {
                                Text("Scheduled: " + delivery.date.formatted()).font(.caption)
                            }
                            if let error = row.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                            Text("Sends while Dispatch is open and online.").font(.caption).foregroundStyle(.secondary)
                            Button("Cancel send and return to Drafts") {
                                do { try runtime.repository?.cancelScheduled(row.id); try session.reloadDrafts() }
                                catch { errors[row.id] = error.localizedDescription }
                            }
                        } else { Button {
                            check(row)
                        } label: {
                            HStack {
                                Text("Check Sent in Gmail")
                                if checking.contains(row.id) { Spacer(); ProgressView() }
                            }
                        }.disabled(checking.contains(row.id)) }
                        if let error = errors[row.id] { Text(error).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Outbox")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func check(_ row: OutgoingMessage) {
        guard !checking.contains(row.id), let gmail = runtime.gmail else { return }
        checking.insert(row.id); errors[row.id] = nil
        Task {
            defer { checking.remove(row.id) }
            do {
                let found = try await gmail.confirmSent(row)
                if !found {
                    errors[row.id] = "No sent copy was found yet. Gmail search can take time to update. Check Gmail before creating another copy."
                }
            } catch { errors[row.id] = error.localizedDescription }
        }
    }
}
