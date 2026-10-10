import SwiftUI

/// Mailbox navigation uses the system sheet's safe areas and dismissal gestures.
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
    @AppStorage("savedMailSearches") private var savedRaw = "[]"
    let openSubscriptions: () -> Void

    @State private var moreMailboxes = false
    @State private var detent: PresentationDetent = .height(530)

    private var selectedAccount: MailAccount? { accounts.first { $0.id.uuidString == account } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if accounts.isEmpty { accountSummary }
                    else {
                        Menu {
                            Picker("Account", selection: $account) {
                                Text("All accounts").tag("")
                                ForEach(accounts) { row in
                                    Text(MailStyle.accountTitle(row, unread: accountCounts[row.id] ?? 0)).tag(row.id.uuidString)
                                }
                            }
                        } label: { accountSummary }.buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(["Inbox", "Unread", "Starred", "Sent"], id: \.self) { name in
                            mailboxButton(name)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        shortcut("Tasks", symbol: "checklist", action: openTasks)
                        shortcut("Receipts", symbol: "receipt", action: openReceipts)
                        shortcut("Attachments", symbol: "paperclip", action: openAttachments)
                        shortcut("People", symbol: "person.2", action: openPeople)
                        shortcut("Collections", symbol: "folder", action: openCollections)
                        shortcut("Subscriptions", symbol: "newspaper", action: openSubscriptions)
                    }
                    DisclosureGroup("More mailboxes", isExpanded: $moreMailboxes) {
                        ForEach(["All Mail", "Drafts", "Archive", "Snoozed", "Spam", "Trash"], id: \.self) { name in
                            mailboxButton(name)
                        }
                    }.font(.subheadline).padding(.horizontal, 14)
                    if let selectedAccount {
                        let labels = folders.filter { $0.accountID == selectedAccount.id && $0.kindRaw == "user" }
                        if !labels.isEmpty {
                            DisclosureGroup("Labels") {
                                ForEach(labels) { folder in
                                    Button {
                                        feedback.select(); label = folder.remoteID; dismiss()
                                    } label: {
                                        mailboxRow(folder.name, symbol: "tag", selected: label == folder.remoteID, count: labelCounts[folder.remoteID] ?? 0)
                                    }.buttonStyle(.plain)
                                        .accessibilityIdentifier("mailLabel-\(folder.remoteID)")
                                }
                            }
                        }
                    }
                    DisclosureGroup("Custom inboxes and smart folders") {
                        ForEach(SavedMailSearch.decode(savedRaw).filter { search in search.accountID == nil || accounts.contains { $0.id == search.accountID } }) { search in
                            Button {
                                feedback.select(); mailbox = "All Mail"; label = "smart:" + search.id.uuidString; dismiss()
                            } label: { mailboxRow(search.name, symbol: "line.3.horizontal.decrease.circle", selected: label == "smart:" + search.id.uuidString, count: 0) }
                        }
                        Button("Create smart folder", systemImage: "plus", action: openSearch)
                    }.font(.subheadline).padding(.horizontal, 14)
                    NavigationLink("Organisation rules") { MailRulesView() }
                    Text("Counts include mail saved on this device.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14)
                }.padding(16)
            }
            .navigationTitle("Mailboxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Accounts", systemImage: "person.crop.circle", action: openAccounts)
                        .labelStyle(.iconOnly).accessibilityIdentifier("mailboxProfileMenu")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape", action: openSettings)
                        .labelStyle(.iconOnly).accessibilityIdentifier("mailboxSettingsButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    MailCloseButton(title: "Close mailboxes") { dismiss() }
                        .accessibilityIdentifier("closeMailboxesButton")
                }
            }
        }
        .presentationDetents([.height(530), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(.regularMaterial)
        .onChange(of: account) { _, _ in feedback.select(); label = nil }
        .onChange(of: moreMailboxes) { _, expanded in if expanded { detent = .large } }
    }

    private func mailboxButton(_ name: String) -> some View {
        Button {
            feedback.select(); label = nil; mailbox = name; dismiss()
        } label: {
            mailboxRow(name, symbol: MailStyle.mailboxSymbol(name), selected: mailbox == name && label == nil, count: counts[name] ?? 0)
        }.buttonStyle(.plain).accessibilityIdentifier("mailbox-\(name)")
    }
    private func shortcut(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { feedback.select(); action() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity, minHeight: 64)
                .background(MailStyle.tile, in: .rect(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("mailbox-\(title)")
    }

    private var accountSummary: some View {
        HStack(spacing: 12) {
            AccountBadge(account: selectedAccount)
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedAccount?.displayName ?? (accounts.isEmpty ? "Sample mail" : "All accounts"))
                    .font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(selectedAccount?.email ?? (accounts.isEmpty ? "On this device" : "\(accounts.count) connected accounts"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !accounts.isEmpty {
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }.padding(10).background(MailStyle.tile, in: .rect(cornerRadius: 20))
    }

    private func mailboxRow(_ name: String, symbol: String, selected: Bool, count: Int = 0) -> some View {
        HStack(spacing: 8) {
            Image(systemName: selected ? symbol + (symbol == "tray" || symbol == "star" || symbol == "archivebox" ? ".fill" : "") : symbol)
                .font(.system(size: 18, weight: selected ? .semibold : .regular)).frame(width: 24)
            Text(name).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1).layoutPriority(1)
            Spacer()
            if count > 0 {
                Text(count, format: .number).font(.subheadline.monospacedDigit())
                    .foregroundStyle(selected ? MailStyle.accent : .secondary)
                    .accessibilityLabel("\(count) cached \(name == "Drafts" ? "drafts" : "unread messages")")
            }
            if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
        }
        .foregroundStyle(selected ? MailStyle.accent : .primary)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(selected ? MailStyle.accent.opacity(0.14) : MailStyle.tile, in: .rect(cornerRadius: 14))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(count > 0 ? "\(count) cached \(name == "Drafts" ? "drafts" : "unread messages")" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct AccountBadge: View {
    let account: MailAccount?
    var body: some View {
        Group {
            if let account {
                Text(String(account.displayName.prefix(1)).uppercased())
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(mailHex: account.colourHex).opacity(0.1), in: .circle)
            } else {
                Image(systemName: "tray.2.fill").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MailStyle.accent).frame(width: 36, height: 36)
                    .background(MailStyle.accent.opacity(0.08), in: .circle)
            }
        }.accessibilityHidden(true)
    }
}
