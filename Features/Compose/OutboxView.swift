import SwiftUI
import SwiftData

struct OutboxView: View {
    @Environment(AppRuntime.self) private var runtime
    @Query(filter: #Predicate<OutgoingMessage> { $0.stateRaw == "sendUnconfirmed" }, sort: \OutgoingMessage.updatedAt, order: .reverse)
    private var outgoing: [OutgoingMessage]
    @Query private var accounts: [MailAccount]
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
                        Button {
                            check(row)
                        } label: {
                            HStack {
                                Text("Check Sent in Gmail")
                                if checking.contains(row.id) { Spacer(); ProgressView() }
                            }
                        }.disabled(checking.contains(row.id))
                        if let error = errors[row.id] { Text(error).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Send confirmations")
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
