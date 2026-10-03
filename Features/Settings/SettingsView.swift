import SwiftUI

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
    @AppStorage("showSampleInbox") private var showSamples = false
    @AppStorage("remoteImages") private var remoteImages = false
    @AppStorage("senderPictures") private var senderPictures = true
    @AppStorage("leadingSwipe") private var leadingSwipe = "read"
    @AppStorage("trailingSwipe") private var trailingSwipe = "archive"
    @AppStorage("fullSwipe") private var fullSwipe = false
    @AppStorage("previewLines") private var previewLines = 2
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Section("Reading") {
                Toggle("Load remote images", isOn: $remoteImages)
                Text("Remote images can tell senders when you open their mail. You can also load images for one message in the reader.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show company icons", isOn: $senderPictures)
                Text("Loads website icons from the sender’s domain. Icons are decorative and do not verify a sender’s identity.")
                    .font(.caption).foregroundStyle(.secondary)
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
            Section("Inbox") {
                Picker("Preview lines", selection: $previewLines) {
                    ForEach(0...3, id: \.self) { Text($0 == 0 ? "Off" : "\($0)").tag($0) }
                }
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Show sample inbox", isOn: $showSamples).accessibilityIdentifier("sampleInboxToggle")
            }
            Section { NavigationLink("Manage accounts") { AccountsView() } }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                Text("Made for a calmer inbox. Gmail is cached on this device. Zoho is coming soon.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
