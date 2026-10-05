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

    private var selectedAccount: MailAccount? { accounts.first { $0.id.uuidString == account } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
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

                    VStack(spacing: 4) {
                        ForEach(MailboxScope.names, id: \.self) { name in
                            Button {
                                feedback.select(); label = nil; mailbox = name; dismiss()
                            } label: {
                                mailboxRow(name, symbol: MailStyle.mailboxSymbol(name), selected: mailbox == name && label == nil,
                                           count: counts[name] ?? 0)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("mailbox-\(name)")
                        }
                    }
                    if let selectedAccount {
                        let labels = folders.filter { $0.accountID == selectedAccount.id && $0.kindRaw == "user" }
                        if !labels.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Labels").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 14)
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
                    VStack(spacing: 4) {
                        Button(action: openTasks) { mailboxRow("Tasks", symbol: "checklist", selected: false) }
                            .buttonStyle(.plain).accessibilityIdentifier("mailbox-Tasks")
                        Button(action: openReceipts) { mailboxRow("Receipts", symbol: "receipt", selected: false) }
                            .buttonStyle(.plain).accessibilityIdentifier("mailbox-Receipts")
                    }
                    Text("Counts include mail saved on this device.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14)
                }.padding(20)
            }
            .navigationTitle("Mailboxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Accounts and settings", systemImage: "person.crop.circle") {
                        Button("Accounts", systemImage: "person.crop.circle", action: openAccounts)
                        Button("Settings", systemImage: "gearshape", action: openSettings)
                    }.accessibilityIdentifier("mailboxProfileMenu")
                }
                ToolbarItem(placement: .confirmationAction) {
                    MailCloseButton(title: "Close mailboxes") { dismiss() }
                        .accessibilityIdentifier("closeMailboxesButton")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(.regularMaterial)
        .onChange(of: account) { _, _ in feedback.select(); label = nil }
    }

    private var accountSummary: some View {
        HStack(spacing: 12) {
            AccountBadge(account: selectedAccount)
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedAccount?.displayName ?? (accounts.isEmpty ? "Sample mail" : "All accounts"))
                    .font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(selectedAccount?.email ?? "Your mail, together")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !accounts.isEmpty {
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }.padding(14).background(MailStyle.paper, in: .rect(cornerRadius: 20))
    }

    private func mailboxRow(_ name: String, symbol: String, selected: Bool, count: Int = 0) -> some View {
        HStack(spacing: 14) {
            Image(systemName: selected ? symbol + (symbol == "tray" || symbol == "star" || symbol == "archivebox" ? ".fill" : "") : symbol)
                .font(.system(size: 18, weight: selected ? .semibold : .regular)).frame(width: 24)
            Text(name).font(.body.weight(selected ? .semibold : .regular)).lineLimit(1)
            Spacer()
            if count > 0 {
                Text(count, format: .number).font(.subheadline.monospacedDigit())
                    .foregroundStyle(selected ? MailStyle.accent : .secondary)
                    .accessibilityLabel("\(count) cached \(name == "Drafts" ? "drafts" : "unread messages")")
            }
            if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
        }
        .foregroundStyle(selected ? MailStyle.accent : .primary)
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(minHeight: 48)
        .background(selected ? MailStyle.accent.opacity(0.09) : .clear, in: .rect(cornerRadius: 14))
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
