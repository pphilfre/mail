import SwiftUI

/// A full-window presentation supplies modal focus; only the side panel animates.
struct MailSidebarPresentation<Content: View>: View {
    let dismiss: () -> Void
    @ViewBuilder let content: (@escaping () -> Void) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var closing = false
    var body: some View {
        GeometryReader { geometry in
            let width = min(360, geometry.size.width * 0.88)
            ZStack(alignment: .leading) {
                Color.black.opacity(visible ? 0.22 : 0).ignoresSafeArea()
                    .onTapGesture(perform: close).accessibilityLabel("Close mailboxes").accessibilityAddTraits(.isButton)
                content(close).frame(width: width)
                    .background(MailStyle.paper).shadow(color: .black.opacity(0.15), radius: 16, x: 6)
                    .offset(x: visible ? 0 : -width - 20)
                    .opacity(reduceMotion && !visible ? 0 : 1)
                    .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width < -60 && abs(value.translation.width) > abs(value.translation.height) { close() }
                    })
            }
        }
        .task { await Task.yield(); withAnimation(MailStyle.motion(reduced: reduceMotion)) { visible = true } }
        .accessibilityAction(.escape, close)
    }
    private func close() {
        guard !closing else { return }; closing = true
        withAnimation(MailStyle.motion(reduced: reduceMotion), completionCriteria: .logicallyComplete) { visible = false } completion: { dismiss() }
    }
}

struct MailboxPanel: View {
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
    let close: () -> Void
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
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(["Inbox", "Unread", "Starred", "Drafts"], id: \.self) { name in
                            Button { select(name) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: MailStyle.mailboxSymbol(name)).foregroundStyle(mailbox == name && label == nil ? MailStyle.accent : .secondary)
                                        Spacer()
                                        if let count = counts[name], count > 0 { Text(count, format: .number).monospacedDigit() }
                                    }
                                    Text(name).font(.subheadline.weight(.medium))
                                }.foregroundStyle(.primary).padding(12).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                                    .background(mailbox == name && label == nil ? MailStyle.accent.opacity(0.1) : MailStyle.tile, in: .rect(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityIdentifier("mailbox-\(name)")
                                .accessibilityAddTraits(mailbox == name && label == nil ? [.isSelected] : [])
                        }
                    }.listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)).listRowBackground(Color.clear)
                }
                Section("Mailboxes") {
                    ForEach(["Sent", "Archive", "Snoozed", "All Mail", "Spam", "Trash"], id: \.self) { name in
                        Button { select(name) } label: {
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
                                    Button { feedback.select(); label = folder.remoteID; close() } label: {
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
                                label = "smart:" + search.id.uuidString; close()
                            } label: { row(search.name, symbol: "line.3.horizontal.decrease", selected: label == "smart:" + search.id.uuidString) }
                        }
                        Button("Create smart folder", systemImage: "plus", action: openSearch)
                    }
                    NavigationLink { MailRulesView() } label: { row("Rules", symbol: "line.3.horizontal.decrease", selected: false) }
                }
                Section {
                    shortcut("Tasks", "checklist", .secondary, openTasks)
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
            }.listStyle(.insetGrouped).tint(.primary).environment(\.defaultMinListRowHeight, 44)
                .navigationTitle("Mailboxes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    MailCloseButton(title: "Close mailboxes", action: close).accessibilityIdentifier("closeMailboxesButton")
                } }
        }.accessibilityAddTraits(.isModal)
            .onChange(of: account) { _, _ in
                feedback.select()
                let search = SavedMailSearch.decode(savedRaw).first { "smart:" + $0.id.uuidString == label }
                if search == nil || (search?.accountID?.uuidString ?? "") != account { label = nil }
            }
    }
    private func select(_ name: String) { feedback.select(); label = nil; mailbox = name; close() }
    private func row(_ title: String, symbol: String, selected: Bool, count: Int = 0) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(selected ? MailStyle.accent : .secondary).frame(width: 24)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if count > 0 { Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
            if selected { Image(systemName: "checkmark").foregroundStyle(MailStyle.accent).fontWeight(.semibold) }
        }.padding(.vertical, 2).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func shortcut(_ title: String, _ symbol: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button { feedback.select(); action() } label: {
            Label { Text(title).foregroundStyle(.primary) } icon: { Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24) }
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
