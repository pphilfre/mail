import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppSession.self) private var session
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
                Section(account.email) {
                    Label("Gmail", systemImage: "envelope")
                    if let date = account.lastSyncAt { LabeledContent("Last sync", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    if let error = account.lastSyncError { Text(error).foregroundStyle(.red) }
                    Button("Sync now") { Task { await runtime.gmail?.sync(account.id) } }
                        .disabled(runtime.gmail?.syncing.contains(account.id) == true)
                    Button("Reconnect Gmail") { Task { await runtime.gmail?.connect() } }
                        .disabled(runtime.gmail?.connecting == true)
                    Button("Remove account", role: .destructive) { removing = account }
                        .disabled(runtime.gmail?.syncing.contains(account.id) == true || runtime.gmail?.writing.contains(account.id) == true)
                }
            }
            Section {
                Button { Task { await runtime.gmail?.connect() } } label: {
                    Label(runtime.gmail?.connecting == true ? "Connecting…" : "Connect Gmail", systemImage: "plus")
                }.disabled(runtime.gmail?.connecting == true)
                if let error = runtime.gmail?.error { Text(error).foregroundStyle(.red) }
            } footer: {
                Text("Google handles sign-in. Dispatch keeps credentials in Keychain and cached mail on this device. Zoho is planned for a later stage.")
            }
        }
        .navigationTitle("Accounts")
        .confirmationDialog("Remove this account and its cached mail and drafts?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove account", role: .destructive) {
                if let id = removing?.id { Task { await runtime.gmail?.removeAccount(id); try? session.reloadDrafts() } }
                removing = nil
            }
        }
    }
}
