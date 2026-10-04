import SwiftUI
import SwiftData

struct PendingActionsView: View {
    var accountID: UUID? = nil
    @Environment(AppRuntime.self) private var runtime
    @Query(sort: \PendingMailOperation.createdAt) private var operations: [PendingMailOperation]
    @Query private var accounts: [MailAccount]
    @Query private var messages: [MailMessage]
    private var scoped: [PendingMailOperation] { operations.filter { accountID == nil || $0.accountID == accountID } }
    var body: some View {
        List {
            if scoped.isEmpty {
                ContentUnavailableView("All changes saved", systemImage: "checkmark.circle",
                    description: Text("There are no queued mailbox changes."))
            }
            ForEach(accounts.filter { account in scoped.contains { $0.accountID == account.id } }) { account in
                Section {
                    ForEach(scoped.filter { $0.accountID == account.id }) { operation in
                        VStack(alignment: .leading, spacing: 4) {
                            if let message = messages.first(where: { $0.accountID == operation.accountID && $0.remoteID == operation.targetRemoteID }) {
                                Text(message.subject.isEmpty ? "No subject" : message.subject).font(.subheadline).lineLimit(1)
                            }
                            Text(title(operation.kindRaw)).font(.subheadline.bold())
                            Text(operation.nextAttemptAt == .distantFuture ? "Needs retry · Later changes to this message are waiting" : "Waiting to sync")
                                .font(.caption).foregroundStyle(.secondary)
                            if let error = operation.lastError { Text(error).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button("Retry mailbox changes") { Task { await runtime.gmail?.retryOperations(account.id) } }
                        .disabled(runtime.gmail == nil || runtime.gmail?.syncing.contains(account.id) == true)
                    NavigationLink("Account settings") { AccountsView() }
                } header: { Text(account.displayName) }
            }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Mailbox changes")
    }
    private func title(_ kind: String) -> String {
        switch kind {
        case "read": "Mark read"
        case "unread": "Mark unread"
        case "archive": "Archive"
        case "trash": "Move to Trash"
        case "restore": "Restore"
        case "spam": "Move to Spam"
        case "notSpam": "Not spam"
        case "star": "Star"
        case "unstar": "Unstar"
        default: "Update label"
        }
    }
}
