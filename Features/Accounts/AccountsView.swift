import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(AppRuntime.self) private var runtime
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @State private var addingAccount = false
    var body: some View {
        List {
            Section("Connected accounts") {
                if accounts.isEmpty {
                    ContentUnavailableView("Connect your first account", systemImage: "envelope.badge",
                        description: Text("Bring your Gmail inbox into Dispatch."))
                }
                ForEach(accounts) { account in
                    NavigationLink { AccountConnectionView(account: account) } label: {
                        HStack(spacing: 14) {
                            AccountBadge(account: account)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(account.displayName).font(.headline)
                                Text(account.email).font(.subheadline).foregroundStyle(MailStyle.secondaryInk)
                                Label(account.lastSyncError == nil ? "Connected" : "Needs attention",
                                      systemImage: account.lastSyncError == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.caption).foregroundStyle(account.lastSyncError == nil ? MailStyle.success : .orange)
                            }
                            Spacer(minLength: 0)
                            if runtime.gmail?.syncing.contains(account.id) == true { ProgressView().controlSize(.small) }
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("account-\(account.email)")
                }
            }
            Section {
                Button { addingAccount = true } label: {
                    HStack(spacing: 10) {
                        if runtime.gmail?.connecting == true { ProgressView() }
                        else { Image(systemName: "plus.circle.fill").font(MailStyle.icon) }
                        Text(runtime.gmail?.connecting == true ? "Connecting…" : "Add Account")
                    }.font(.body.weight(.semibold)).frame(minHeight: 44).foregroundStyle(MailStyle.accent)
                }.buttonStyle(.plain).disabled(runtime.gmail == nil || runtime.gmail?.connecting == true)
                    .accessibilityIdentifier("connectGmailButton")
                if let error = runtime.gmail?.error { Text(error).font(.callout).foregroundStyle(.red) }
            }.listRowSeparator(.hidden)
        }.modifier(MailWorkspaceList()).mailSheetTitle("Accounts")
        .sheet(isPresented: $addingAccount) {
            NavigationStack {
                List {
                    Button {
                        addingAccount = false
                        Task { await runtime.gmail?.connect() }
                    } label: {
                        HStack(spacing: 12) {
                            Image("Google").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                            Text("Google").foregroundStyle(MailStyle.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(MailStyle.secondaryInk)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("googleAccountProvider")
                }.modifier(MailWorkspaceList()).mailSheetTitle("Add Account")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { addingAccount = false } } }
            }.presentationDetents([.medium, .large])
        }
    }
}

private struct AccountConnectionView: View {
    let account: MailAccount
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppSession.self) private var session
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @State private var removing = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AccountBadge(account: account)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName).font(.title3.weight(.semibold))
                        Text(account.email).font(.subheadline).foregroundStyle(MailStyle.secondaryInk).textSelection(.enabled)
                    }
                }.padding(.vertical, 8)
            }
            Section("Make it yours") {
                NavigationLink { AccountPreferencesView(account: account) } label: {
                    Label("Name, colour and signature", systemImage: "slider.horizontal.3")
                }
                NavigationLink { PendingActionsView(accountID: account.id) } label: {
                    Label("Queued mailbox changes", systemImage: "clock.arrow.circlepath")
                }
            }
            Section("Connection") {
                if let deadline = runtime.gmail?.waitingUntil[account.id], deadline > Date() { GmailWaitStatus(deadline: deadline) }
                else {
                    Label(account.lastSyncError == nil ? "Connected to Gmail" : "Connection needs attention",
                          systemImage: account.lastSyncError == nil ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(account.lastSyncError == nil ? MailStyle.success : .orange)
                }
                if let date = account.lastSyncAt { LabeledContent("Last updated", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let error = account.lastSyncError { Text(error).font(.callout).foregroundStyle(.red) }
                Button {
                    feedback.select()
                    Task {
                        await runtime.gmail?.sync(account.id)
                        if runtime.gmail != nil && account.lastSyncError == nil { feedback.show("Mail is up to date", symbol: "arrow.clockwise") }
                    }
                } label: {
                    HStack {
                        Label("Sync now", systemImage: "arrow.clockwise")
                        Spacer()
                        if runtime.gmail?.syncing.contains(account.id) == true { ProgressView().controlSize(.small) }
                    }
                }.disabled(runtime.gmail?.syncing.contains(account.id) == true)
                Button("Reconnect Gmail", systemImage: "arrow.triangle.2.circlepath") { Task { await runtime.gmail?.connect() } }
                    .disabled(runtime.gmail?.connecting == true)
            }
            Section {
                Button("Remove account", systemImage: "person.crop.circle.badge.minus", role: .destructive) { removing = true }
                    .disabled(runtime.gmail?.syncing.contains(account.id) == true || runtime.gmail?.writing.contains(account.id) == true)
            } footer: { Text("Removing an account also removes its cached mail and drafts from this device.") }
        }.modifier(MailWorkspaceList()).mailSheetTitle("Account")
            .confirmationDialog("Remove this account and its cached mail and drafts?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove account", role: .destructive) {
                    Task { await runtime.gmail?.removeAccount(account.id); try? session.reloadDrafts(); dismiss() }
                }
            }
    }
}
