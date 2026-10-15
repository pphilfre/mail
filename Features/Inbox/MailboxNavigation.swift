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
              Group {
                Section {
                    Menu {
                        Picker("Account", selection: $account) {
                            Text("All accounts").tag("")
                            ForEach(accounts) { Text(MailStyle.accountTitle($0, unread: accountCounts[$0.id] ?? 0)).tag($0.id.uuidString) }
                        }
                    } label: {
                        HStack {
                            AccountBadge(account: selectedAccount)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedAccount?.displayName ?? (accounts.isEmpty ? "Sample mail" : "All accounts"))
                                    .font(.headline).foregroundStyle(MailStyle.ink)
                                if let selectedAccount { Text(selectedAccount.email).font(.footnote).foregroundStyle(MailStyle.secondaryInk) }
                            }
                            Spacer()
                            if !accounts.isEmpty { Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(MailStyle.secondaryInk) }
                        }
                    }.disabled(accounts.isEmpty)
                }
                Section {
                    ForEach(["Inbox", "Unread", "Starred", "Drafts"], id: \.self) { name in
                        Button { select(name) } label: {
                            row(name, symbol: MailStyle.mailboxSymbol(name), selected: mailbox == name && label == nil, count: counts[name] ?? 0)
                        }.buttonStyle(.plain).accessibilityIdentifier("mailbox-\(name)")
                            .accessibilityAddTraits(mailbox == name && label == nil ? [.isSelected] : [])
                    }
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
                    DisclosureGroup("Saved searches") {
                        ForEach(SavedMailSearch.decode(savedRaw).filter { search in search.accountID == nil || accounts.contains { $0.id == search.accountID } }) { search in
                            Button {
                                feedback.select(); account = search.accountID?.uuidString ?? ""; mailbox = "All Mail"
                                label = "smart:" + search.id.uuidString; close()
                            } label: { row(search.name, symbol: "line.3.horizontal.decrease", selected: label == "smart:" + search.id.uuidString) }
                        }
                        Button("Create saved search", systemImage: "plus", action: openSearch)
                    }
                    NavigationLink { MailRulesView() } label: { row("Rules", symbol: "line.3.horizontal.decrease", selected: false) }
                }
                Section {
                    shortcut("Tasks", "checklist", openTasks)
                    shortcut("Receipts", "receipt", openReceipts)
                    shortcut("Attachments", "paperclip", openAttachments)
                    shortcut("People", "person.2", openPeople)
                    shortcut("Collections", "folder", openCollections)
                    shortcut("Subscriptions", "newspaper", openSubscriptions)
                }
              }
              .listRowBackground(MailStyle.paper)
              .listRowInsets(EdgeInsets(top: 0, leading: MailStyle.contentPadding, bottom: 0, trailing: MailStyle.contentPadding))
              .listRowSeparator(.hidden)
              .textCase(nil)
            }.modifier(MailWorkspaceList())
                .listSectionSpacing(.custom(10))
                .environment(\.defaultMinListRowHeight, 44)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        MailRule()
                        HStack(spacing: 12) {
                            Spacer(minLength: 0)
                            Button("Accounts", systemImage: "person.crop.circle", action: openAccounts)
                                .accessibilityIdentifier("mailbox-Accounts")
                            Button("Settings", systemImage: "gearshape", action: openSettings)
                                .accessibilityIdentifier("mailboxSettingsButton")
                        }.font(.subheadline.weight(.medium)).buttonStyle(.plain)
                            .frame(minHeight: 56).padding(.horizontal, 16)
                    }.background(MailStyle.paper)
                }
                .navigationTitle("Mailboxes").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                  ToolbarItem(placement: .principal) { MailNavigationTitle(title: "Mailboxes") }
                  ToolbarItem(placement: .confirmationAction) {
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
            Image(systemName: symbol).font(MailStyle.icon).foregroundStyle(selected ? MailStyle.accent : MailStyle.secondaryInk).frame(width: 24)
            Text(title).font(.body.weight(selected ? .semibold : .regular)).foregroundStyle(MailStyle.ink)
            Spacer()
            if count > 0 { Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(MailStyle.secondaryInk) }
            if selected { Image(systemName: "checkmark").foregroundStyle(MailStyle.accent).fontWeight(.semibold) }
        }.frame(minHeight: 44).contentShape(.rect).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func shortcut(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { feedback.select(); action() } label: {
            row(title, symbol: symbol, selected: false)
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
