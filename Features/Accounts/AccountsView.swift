import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppSession.self) private var session
    @Environment(MailFeedback.self) private var feedback
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @State private var removing: MailAccount?
    var body: some View {
        List {
            if accounts.isEmpty { Section {
                ContentUnavailableView("No accounts connected", systemImage: "person.crop.circle.badge.plus",
                    description: Text("Connect Gmail to read and send mail in Dispatch."))
                    .listRowBackground(Color.clear)
            } }
            ForEach(accounts) { account in
                Section {
                    HStack(spacing: 14) {
                        SenderAvatar(email: account.email, name: account.displayName)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.displayName).font(.subheadline.weight(.semibold))
                            Text(account.email).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }.padding(.vertical, 8)
                    HStack(spacing: 6) {
                        if let deadline = runtime.gmail?.waitingUntil[account.id], deadline > Date() {
                            GmailWaitStatus(deadline: deadline)
                        } else {
                            Label(account.lastSyncError == nil ? "Connected to Gmail" : "Connection needs attention", systemImage: account.lastSyncError == nil ? "checkmark.circle" : "exclamationmark.circle")
                                .font(.caption).foregroundStyle(account.lastSyncError == nil ? MailStyle.success : .orange)
                        }
                        Spacer()
                        if runtime.gmail?.syncing.contains(account.id) == true { ProgressView() }
                    }
                    if let date = account.lastSyncAt { LabeledContent("Last updated", value: date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline) }
                    if let error = account.lastSyncError { Text(error).font(.callout).foregroundStyle(.red) }
                    Button("Sync now", systemImage: "arrow.clockwise") {
                        feedback.select()
                        Task {
                            await runtime.gmail?.sync(account.id)
                            if runtime.gmail != nil && account.lastSyncError == nil {
                                feedback.show("Mail is up to date", symbol: "arrow.clockwise")
                            }
                        }
                    }
                        .disabled(runtime.gmail?.syncing.contains(account.id) == true)
                    NavigationLink { AccountPreferencesView(account: account) } label: { Label("Nickname, colour and signature", systemImage: "slider.horizontal.3") }
                    NavigationLink { PendingActionsView(accountID: account.id) } label: { Label("Queued mailbox changes", systemImage: "clock.arrow.circlepath") }
                    DisclosureGroup("Connection options") {
                        Button("Reconnect Gmail", systemImage: "arrow.triangle.2.circlepath") { Task { await runtime.gmail?.connect() } }
                            .disabled(runtime.gmail?.connecting == true)
                        Button("Remove account", systemImage: "person.crop.circle.badge.minus", role: .destructive) { removing = account }
                            .disabled(runtime.gmail?.syncing.contains(account.id) == true || runtime.gmail?.writing.contains(account.id) == true)
                    }.font(.subheadline)
                }
            }
            Section {
                Button { Task { await runtime.gmail?.connect() } } label: {
                    HStack {
                        if runtime.gmail?.connecting == true { ProgressView() }
                        Image(systemName: "envelope.badge").font(.title3)
                        Text(runtime.gmail?.connecting == true ? "Connecting…" : "Connect Gmail")
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                    }.font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .disabled(runtime.gmail == nil || runtime.gmail?.connecting == true)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("connectGmailButton")
                if let error = runtime.gmail?.error { Text(error).foregroundStyle(.red) }
            } footer: {
                Text("Google handles sign-in. Dispatch keeps credentials in Keychain and cached mail on this device. Zoho is planned for a later stage.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(MailStyle.canvas)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .font(.subheadline)
        .confirmationDialog("Remove this account and its cached mail and drafts?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove account", role: .destructive) {
                if let id = removing?.id { Task { await runtime.gmail?.removeAccount(id); try? session.reloadDrafts() } }
                removing = nil
            }
        }
    }
}
