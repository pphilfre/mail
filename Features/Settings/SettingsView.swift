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
        case .read: MailStyle.accent
        case .archive: MailStyle.accent
        case .trash: .red
        case .star: MailStyle.accent
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
    @AppStorage("compactInbox") private var compactInbox = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("conversationRows") private var conversationRows = true
    @AppStorage("hapticFeedback") private var haptics = true
    @AppStorage("confirmationAnimations") private var confirmationAnimations = true

    var body: some View {
        List {
          Group {
            Section {
                NavigationLink { AccountsView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle")
                            .font(.title2).foregroundStyle(.white)
                            .frame(width: 32, height: 44)
                        Text("Accounts").font(.body)
                    }.padding(.vertical, 4)
                }
            }
            Section("Privacy") {
                NavigationLink { MailIntegrationSettings() } label: { SettingsLabel("Privacy & AI", symbol: "hand.raised") }
                    .accessibilityIdentifier("privacyIntelligenceSettingsLink")
            }
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
            }
            Section {
                Toggle(isOn: $remoteImages) { HStack { Image(systemName: "photo").foregroundStyle(.white).frame(width: 28); MailInfoLabel(title: "Remote images", information: "Loading images can reveal when you open mail.") } }.accessibilityIdentifier("remoteImagesToggle")
                Toggle(isOn: $senderPictures) { HStack { Image(systemName: "building.2").foregroundStyle(.white).frame(width: 28); MailInfoLabel(title: "Company icons", information: "Icons load from senders’ websites. They do not verify identity.") } }
                Toggle(isOn: $compactInbox) { SettingsLabel("Compact inbox", symbol: "rectangle.compress.vertical") }.accessibilityIdentifier("compactInboxToggle")
                Picker(selection: $previewLines) {
                    ForEach(0...3, id: \.self) { Text($0 == 0 ? "Off" : "\($0)").tag($0) }
                } label: { SettingsLabel("Preview lines", symbol: "text.alignleft") }.accessibilityIdentifier("previewLinesPicker")
                Toggle(isOn: $conversationRows) { SettingsLabel("Group conversations", symbol: "bubble.left.and.bubble.right") }
            } header: { Text("Reading").font(MailStyle.sectionHeading).foregroundStyle(MailStyle.secondaryInk) }
            if !accounts.isEmpty {
                Section("Composing") {
                    Picker(selection: $defaultAccount) {
                        Text("Use selected account").tag("")
                        ForEach(accounts) { Text($0.displayName).tag($0.id.uuidString) }
                    } label: { SettingsLabel("Send from", symbol: "paperplane") }
                    ForEach(accounts) { account in
                        NavigationLink { AccountPreferencesView(account: account) } label: { SettingsLabel("Signature · \(account.displayName)", symbol: "signature") }
                    }
                }
            }
            Section("Swipe actions") {
                Picker(selection: $leadingSwipe) {
                    ForEach(MailSwipeAction.allCases) { Text($0.title).tag($0.rawValue) }
                } label: { SettingsLabel("Swipe right", symbol: "arrow.right") }.accessibilityIdentifier("leadingSwipePicker")
                Picker(selection: $trailingSwipe) {
                    ForEach(MailSwipeAction.allCases) { Text($0.title).tag($0.rawValue) }
                } label: { SettingsLabel("Swipe left", symbol: "arrow.left") }
                Toggle(isOn: $fullSwipe) { SettingsLabel("Full swipe", symbol: "hand.draw") }
            }
            Section {
                Toggle(isOn: $haptics) { SettingsLabel("Haptic feedback", symbol: "waveform") }.accessibilityIdentifier("hapticFeedbackToggle")
                Toggle(isOn: $confirmationAnimations) { SettingsLabel("Confirmation animations", symbol: "checkmark.circle") }.accessibilityIdentifier("confirmationAnimationsToggle")
            } header: { Text("Feedback").font(MailStyle.sectionHeading).foregroundStyle(MailStyle.secondaryInk) }
            Section("Sample mail") {
                Toggle(isOn: $showSamples) { SettingsLabel("Show sample inbox", symbol: "tray") }.accessibilityIdentifier("sampleInboxToggle")
            }
            Section("About") {
                LabeledContent { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") } label: { SettingsLabel("Version", symbol: "info.circle") }

            }
          }
          .listRowBackground(MailStyle.paper)
          .listRowInsets(EdgeInsets(top: 12, leading: MailStyle.contentPadding, bottom: 12, trailing: MailStyle.contentPadding))
          .textCase(nil)
        }
        .modifier(MailWorkspaceList())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { MailNavigationTitle(title: "Settings") } }
        .onChange(of: appearance) { _, _ in feedback.select() }
        .onChange(of: haptics) { _, enabled in if enabled { feedback.select() } }
        .onChange(of: confirmationAnimations) { _, enabled in
            if enabled { feedback.show("Confirmation animations enabled", detail: "You’re all set") }
        }
    }
}

private struct SettingsLabel: View {
    let title: String
    let symbol: String
    init(_ title: String, symbol: String) { self.title = title; self.symbol = symbol }
    var body: some View {
        Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(.white).frame(width: 28) }
    }
}
