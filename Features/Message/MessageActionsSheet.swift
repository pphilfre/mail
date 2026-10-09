import SwiftUI
import SwiftData

enum MessageSheetAction {
    case reply, replyAll, forward, triage(String), sender, contact, task, receipt, collection
    case security, translate, printMessage, savePDF, saveEML, unsubscribe, forwardAttachment, calendar
    case pin(Bool), snooze(Date), unsnooze
}

struct MessageActionsSheet: View {
    @Query private var metadata: [StoreMetadata]
    let message: MailMessage
    let folders: [MailFolder]
    let organisation: MailLocalOrganisation
    let choose: (MessageSheetAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.dynamicTypeSize) private var typeSize
    private var hasUnsubscribe: Bool {
        guard let row = metadata.first(where: { $0.key == MailUnsubscribe.key(message) }),
              let value = try? JSONDecoder().decode(MailUnsubscribe.self, from: Data(row.value.utf8)) else { return false }
        return value.web != nil || value.mail != nil
    }
    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    SenderAvatar(email: message.senderEmail, name: message.sender.displayName)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.sender.displayName).font(.headline)
                        Text(message.subject).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.padding(.vertical, 4)
                if !message.isDraft {
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack { quick("Reply", "arrowshape.turn.up.left", .reply); quick("Reply All", "arrowshape.turn.up.left.2", .replyAll); quick("Forward", "arrowshape.turn.up.right", .forward) }
                        } else {
                            HStack { quick("Reply", "arrowshape.turn.up.left", .reply); quick("Reply All", "arrowshape.turn.up.left.2", .replyAll); quick("Forward", "arrowshape.turn.up.right", .forward) }
                        }
                    }.listRowBackground(Color.clear)
                }
            }
            Section {
                row(message.isStarred ? "Unflag" : "Flag", "flag", .triage(message.isStarred ? "unstar" : "star"))
                NavigationLink { folderPicker(move: false) } label: { Label("Tag", systemImage: "tag") }
                    .disabled(folders.filter { $0.kindRaw == "user" }.isEmpty)
                row(organisation.pinned ? "Unpin" : "Pin", "pin", .pin(!organisation.pinned))
                if organisation.isSnoozed(at: Date()) { row(message.isInbox ? "Return to inbox" : "Stop snoozing", "clock.arrow.circlepath", .unsnooze) }
                else {
                    Menu {
                        Button("In one hour") { select(.snooze(Date().addingTimeInterval(3600))) }
                        Button("Tomorrow morning") { select(.snooze(Self.tomorrowMorning())) }
                        Button("In one week") { select(.snooze(Date().addingTimeInterval(7 * 86400))) }
                    } label: { Label("Snooze", systemImage: "clock") }
                }
                row(message.isRead ? "Mark Unread" : "Mark Read", message.isRead ? "envelope.badge" : "envelope.open", .triage(message.isRead ? "unread" : "read"), identifier: "readerReadButton")
            } header: { Text("Organisation") }
              footer: { Text("Pins and snoozes are saved on this device. Flag uses the account’s starred label.") }
            Section("Management") {
                NavigationLink { folderPicker(move: true) } label: { Label("Move", systemImage: "folder") }
                    .disabled(message.isTrash || message.isSpam || message.isDraft)
                row("Archive", "archivebox", .triage("archive")).disabled(!message.isInbox || message.isDraft)
                if message.isTrash { row("Restore", "arrow.uturn.backward", .triage("restore")) }
                else { row("Delete", "trash", .triage("trash"), destructive: true).disabled(message.isDraft) }
            }
            Section("Sender") {
                row("Add Contact", "person.crop.circle.badge.plus", .contact)
                row("Show Emails", "envelope", .sender)

                row(message.isSpam ? "Not Spam" : "Spam", "exclamationmark.shield", .triage(message.isSpam ? "notSpam" : "spam"), destructive: !message.isSpam)
            }
            Section {
                row("Translate", "character.bubble", .translate)
                row("Print", "printer", .printMessage)
                row("Save PDF", "doc.richtext", .savePDF)
                row("Save EML", "doc", .saveEML)
                if hasUnsubscribe {
                    row("Unsubscribe", "envelope.badge.minus", .unsubscribe)
                }
                if !message.isDraft { row("Forward as Attachment", "paperclip", .forwardAttachment) }
                row("Create Reminder", "checklist", .task, identifier: "makeMailTaskButton")
                row("Add Calendar Event", "calendar.badge.plus", .calendar)
                if !message.isDraft {
                    row("Add to collection", "folder.badge.plus", .collection, identifier: "addToCollectionButton")
                    row("Save receipt", "receipt", .receipt, identifier: "makeReceiptButton")
                }
            } header: { Text("Tools") }

            Section("Security") { row("Open Security Inspector", "checkmark.shield", .security) }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, 44)
        .navigationTitle("Message actions").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { dismiss() } } }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private func select(_ action: MessageSheetAction) { feedback.select(); choose(action) }
    private func row(_ title: String, _ symbol: String, _ action: MessageSheetAction, destructive: Bool = false, identifier: String? = nil) -> some View {
        Button(role: destructive ? .destructive : nil) { select(action) } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .accessibilityIdentifier(identifier ?? title).accessibilityLabel(title)
        .buttonStyle(.plain).foregroundStyle(destructive ? Color.red : Color.primary)
    }
    private func quick(_ title: String, _ symbol: String, _ action: MessageSheetAction) -> some View {
        Button { select(action) } label: {
            VStack(spacing: 4) { Image(systemName: symbol).font(.title2); Text(title).font(.subheadline) }
                .frame(maxWidth: .infinity, minHeight: 52)
        }.buttonStyle(.glass).accessibilityLabel(title)
    }
    private func folderPicker(move: Bool) -> some View {
        List {
            if move {
                row("Inbox", "tray", .triage("labelAdd:INBOX"))
                row("Archive", "archivebox", .triage("archive"))
            }
            ForEach(folders.filter { $0.kindRaw == "user" }) { folder in
                let hasLabel = message.folderIDs.contains(folder.remoteID)
                row(folder.name, hasLabel ? "checkmark" : "tag", .triage((move ? "move:" : hasLabel ? "labelRemove:" : "labelAdd:") + folder.remoteID))
            }
        }.navigationTitle(move ? "Move message" : "Tags")
    }
    static func tomorrowMorning(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
