import SwiftUI

struct MailboxSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MailFeedback.self) private var feedback
    let accounts: [MailAccount]
    let folders: [MailFolder]
    let counts: [String: Int]
    let accountCounts: [UUID: Int]
    let labelCounts: [String: Int]
    @Binding var account: String
    @Binding var mailbox: String
    @Binding var label: String?
    let openAccounts: () -> Void
    let openSettings: () -> Void
    let openTasks: () -> Void
    let openReceipts: () -> Void
    let openAttachments: () -> Void
    let openPeople: () -> Void
    let openCollections: () -> Void
    let openSearch: () -> Void
    let openSubscriptions: () -> Void
    @AppStorage("savedMailSearches") private var savedRaw = "[]"
    private var selectedAccount: MailAccount? { accounts.first { $0.id.uuidString == account } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Menu {
                        Picker("Account", selection: $account) {
                            Text("All accounts").tag("")
                            ForEach(accounts) { Text(MailStyle.accountTitle($0, unread: accountCounts[$0.id] ?? 0)).tag($0.id.uuidString) }
                        }
                    } label: {
                        HStack {
                            AccountBadge(account: selectedAccount)
                            Text(selectedAccount?.displayName ?? (accounts.isEmpty ? "Sample mail" : "All accounts")).foregroundStyle(.primary)
                            Spacer()
                            if !accounts.isEmpty { Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.disabled(accounts.isEmpty)
                }
                Section {
                    ForEach(["Inbox", "Unread", "Starred", "Sent", "Drafts", "Archive", "Snoozed", "All Mail", "Spam", "Trash"], id: \.self) { name in
                        Button { feedback.select(); label = nil; mailbox = name; dismiss() } label: {
                            row(name, symbol: MailStyle.mailboxSymbol(name), selected: mailbox == name && label == nil, count: counts[name] ?? 0)
                        }.accessibilityIdentifier("mailbox-\(name)")
                    }
                }
                if let selectedAccount {
                    let labels = folders.filter { $0.accountID == selectedAccount.id && $0.kindRaw == "user" }
                    if !labels.isEmpty {
                        Section {
                            DisclosureGroup("Labels") {
                                ForEach(labels) { folder in
                                    Button { feedback.select(); label = folder.remoteID; dismiss() } label: {
                                        row(folder.name, symbol: "tag", selected: label == folder.remoteID, count: labelCounts[folder.remoteID] ?? 0)
                                    }.accessibilityIdentifier("mailLabel-\(folder.remoteID)")
                                }
                            }
                        }
                    }
                }
                Section {
                    DisclosureGroup("Smart folders") {
                        ForEach(SavedMailSearch.decode(savedRaw).filter { search in search.accountID == nil || accounts.contains { $0.id == search.accountID } }) { search in
                            Button {
                                feedback.select(); account = search.accountID?.uuidString ?? ""; mailbox = "All Mail"
                                label = "smart:" + search.id.uuidString; dismiss()
                            } label: { row(search.name, symbol: "line.3.horizontal.decrease", selected: label == "smart:" + search.id.uuidString) }
                        }
                        Button("Create smart folder", systemImage: "plus", action: openSearch)
                    }
                    NavigationLink { MailRulesView() } label: { row("Rules", symbol: "line.3.horizontal.decrease", selected: false) }
                }
                Section {
                    shortcut("Receipts", "receipt", .orange, openReceipts)
                    shortcut("Attachments", "paperclip", .blue, openAttachments)
                    shortcut("People", "person.2", .purple, openPeople)
                    shortcut("Collections", "folder", .teal, openCollections)
                    shortcut("Subscriptions", "newspaper", .pink, openSubscriptions)
                }
                Section {
                    shortcut("Accounts", "person.crop.circle", .blue, openAccounts)
                    shortcut("Settings", "gearshape", .gray, openSettings)
                }
            }.listStyle(.insetGrouped).environment(\.defaultMinListRowHeight, 44)
                .navigationTitle("Mailboxes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    MailCloseButton(title: "Close mailboxes") { dismiss() }.accessibilityIdentifier("closeMailboxesButton")
                } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .onChange(of: account) { _, _ in
                feedback.select()
                let search = SavedMailSearch.decode(savedRaw).first { "smart:" + $0.id.uuidString == label }
                if search == nil || (search?.accountID?.uuidString ?? "") != account { label = nil }
            }
    }
    private func row(_ title: String, symbol: String, selected: Bool, count: Int = 0) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(selected ? MailStyle.accent : .secondary).frame(width: 24)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if count > 0 { Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
            if selected { Image(systemName: "checkmark").foregroundStyle(MailStyle.accent).fontWeight(.semibold) }
        }.accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func shortcut(_ title: String, _ symbol: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button { feedback.select(); action() } label: {
            Label { Text(title).foregroundStyle(.primary) } icon: { Image(systemName: symbol).foregroundStyle(color).frame(width: 24) }
        }.accessibilityIdentifier(title == "Settings" ? "mailboxSettingsButton" : "mailbox-\(title)")
    }
}

struct AccountBadge: View {
    let account: MailAccount?
    var body: some View {
        Group {
            if let account {
                Text(String(account.displayName.prefix(1)).uppercased())
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(mailHex: account.colourHex))
                    .frame(width: 32, height: 32).background(Color(mailHex: account.colourHex).opacity(0.1), in: .circle)
            } else {
                Image(systemName: "tray.2.fill").foregroundStyle(MailStyle.accent)
                    .frame(width: 32, height: 32).background(MailStyle.accent.opacity(0.08), in: .circle)
            }
        }.accessibilityHidden(true)
    }
}
