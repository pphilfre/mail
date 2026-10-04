import SwiftUI
import SwiftData

enum MailSwipeAction: String, CaseIterable, Identifiable {
    case read, archive, trash, star, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .read: "Read / unread"
        case .archive: "Archive"
        case .trash: "Trash / restore"
        case .star: "Star / unstar"
        case .none: "None"
        }
    }
    var symbol: String {
        switch self {
        case .read: "envelope.open"
        case .archive: "archivebox"
        case .trash: "trash"
        case .star: "star"
        case .none: "minus"
        }
    }
    var tint: Color {
        switch self {
        case .read: .blue
        case .archive: .orange
        case .trash: .red
        case .star: .yellow
        case .none: .gray
        }
    }
    func operation(for message: MailMessage) -> String {
        switch self {
        case .read: message.isRead ? "unread" : "read"
        case .trash: message.isTrash ? "restore" : "trash"
        case .star: message.isStarred ? "unstar" : "star"
        default: rawValue
        }
    }
    func label(for message: MailMessage) -> String {
        switch self {
        case .read: message.isRead ? "Mark unread" : "Mark read"
        case .trash: message.isTrash ? "Restore" : "Trash"
        case .star: message.isStarred ? "Unstar" : "Star"
        default: title
        }
    }
}

struct SettingsView: View {
    @Query(sort: \MailAccount.email) private var accounts: [MailAccount]
    @AppStorage("defaultSendingAccount") private var defaultAccount = ""
    @Environment(MailFeedback.self) private var feedback
    @AppStorage("showSampleInbox") private var showSamples = false
    @AppStorage("remoteImages") private var remoteImages = false
    @AppStorage("senderPictures") private var senderPictures = true
    @AppStorage("leadingSwipe") private var leadingSwipe = "read"
    @AppStorage("trailingSwipe") private var trailingSwipe = "archive"
    @AppStorage("fullSwipe") private var fullSwipe = false
    @AppStorage("previewLines") private var previewLines = 2
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("conversationRows") private var conversationRows = true
    @AppStorage("hapticFeedback") private var haptics = true
    @AppStorage("confirmationAnimations") private var confirmationAnimations = true

    var body: some View {
        Form {
            Section {
                NavigationLink { AccountsView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle")
                            .font(.title2).foregroundStyle(MailStyle.accent)
                            .frame(width: 44, height: 44).background(MailStyle.accent.opacity(0.08), in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your accounts").font(.headline)
                            Text("Connections and sync").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section {
                Toggle("Load remote images", isOn: $remoteImages)
                Toggle("Show company icons", isOn: $senderPictures)
                Picker("Preview lines", selection: $previewLines) {
                    ForEach(0...3, id: \.self) { Text($0 == 0 ? "Off" : "\($0)").tag($0) }
                }
                Toggle("Group conversations", isOn: $conversationRows)
            } header: { Text("Reading") } footer: {
                Text("Remote images can reveal when you open mail. Company icons load from senders’ websites and do not verify their identity.")
            }
            if !accounts.isEmpty {
                Section("Composing") {
                    Picker("Default sending account", selection: $defaultAccount) {
                        Text("Use selected account").tag("")
                        ForEach(accounts) { Text($0.displayName).tag($0.id.uuidString) }
                    }
                    ForEach(accounts) { account in
                        NavigationLink("Signature · \(account.displayName)") { AccountPreferencesView(account: account) }
                    }
                    Text("New mail uses the selected inbox account first, then your default. Replies use the receiving account.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Swipe actions") {
                Picker("Swipe right", selection: $leadingSwipe) {
                    ForEach(MailSwipeAction.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Swipe left", selection: $trailingSwipe) {
                    ForEach(MailSwipeAction.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Perform action on full swipe", isOn: $fullSwipe)
            }
            Section("Appearance") {
                Picker("Colour scheme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
            }
            Section {
                Toggle("Haptic feedback", isOn: $haptics).accessibilityIdentifier("hapticFeedbackToggle")
                Toggle("Confirmation animations", isOn: $confirmationAnimations).accessibilityIdentifier("confirmationAnimationsToggle")
            } header: { Text("Feedback") } footer: {
                Text("A little tap and a quick celebration when things are done. Animations follow your device’s Reduce Motion setting.")
            }
            Section("Sample mail") {
                Toggle("Show sample inbox", isOn: $showSamples).accessibilityIdentifier("sampleInboxToggle")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                Text("A little more calm. A lot less inbox.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MailStyle.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: appearance) { _, _ in feedback.select() }
        .onChange(of: haptics) { _, enabled in if enabled { feedback.select() } }
        .onChange(of: confirmationAnimations) { _, enabled in
            if enabled { feedback.show("A little celebration", detail: "You’re all set") }
        }
    }
}
