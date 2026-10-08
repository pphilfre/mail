import SwiftUI

enum MessageSheetAction {
    case reply, replyAll, forward, triage(String), sender, contact, task, receipt, collection
    case security, translate, printMessage, savePDF, forwardAttachment, calendar
    case pin(Bool), snooze(Date), unsnooze
}

struct MessageActionsSheet: View {
    let message: MailMessage
    let folders: [MailFolder]
    let organisation: MailLocalOrganisation
    let choose: (MessageSheetAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MailFeedback.self) private var feedback
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
                    ViewThatFits(in: .horizontal) {
                        HStack { quick("Reply", "arrowshape.turn.up.left", .reply); quick("Reply All", "arrowshape.turn.up.left.2", .replyAll); quick("Forward", "arrowshape.turn.up.right", .forward) }
                        VStack { quick("Reply", "arrowshape.turn.up.left", .reply); quick("Reply All", "arrowshape.turn.up.left.2", .replyAll); quick("Forward", "arrowshape.turn.up.right", .forward) }
                    }.listRowBackground(Color.clear)
                }
            }
            Section("Organisation") {
                row(message.isStarred ? "Unflag" : "Flag", "flag", .triage(message.isStarred ? "unstar" : "star"))
                NavigationLink { folderPicker(move: false) } label: { Label("Tag", systemImage: "tag") }
                    .disabled(folders.filter { $0.kindRaw == "user" }.isEmpty)
                row(organisation.pinned ? "Unpin" : "Pin", "pin", .pin(!organisation.pinned))
                if organisation.isSnoozed(at: Date()) { row("Return to inbox", "clock.arrow.circlepath", .unsnooze) }
                else {
                    Menu {
                        Button("In one hour") { select(.snooze(Date().addingTimeInterval(3600))) }
                        Button("Tomorrow morning") { select(.snooze(Self.tomorrowMorning())) }
                        Button("In one week") { select(.snooze(Date().addingTimeInterval(7 * 86400))) }
                    } label: { Label("Snooze", systemImage: "clock") }
                }
                row(message.isRead ? "Mark Unread" : "Mark Read", message.isRead ? "envelope.badge" : "envelope.open", .triage(message.isRead ? "unread" : "read"))
                    .accessibilityIdentifier("readerReadButton")
            } footer: { Text("Pins and snoozes are saved on this device. Flag uses the account’s starred label.") }
            Section("Management") {
                NavigationLink { folderPicker(move: true) } label: { Label("Move", systemImage: "folder") }
                row("Archive", "archivebox", .triage("archive"))
                if message.isTrash { row("Restore", "arrow.uturn.backward", .triage("restore")) }
                else { row("Delete", "trash", .triage("trash"), destructive: true) }
            }
            Section("Sender") {
                row("Add Contact", "person.crop.circle.badge.plus", .contact)
                row("Show Emails", "envelope", .sender)
                unavailable("Block Sender", "person.crop.circle.badge.xmark")
                row(message.isSpam ? "Not Spam" : "Spam", "exclamationmark.shield", .triage(message.isSpam ? "notSpam" : "spam"), destructive: !message.isSpam)
            }
            Section("Tools") {
                row("Translate", "character.bubble", .translate)
                row("Print", "printer", .printMessage)
                row("Save PDF", "doc.richtext", .savePDF)
                if !message.isDraft { row("Forward as Attachment", "paperclip", .forwardAttachment) }
                row("Create Reminder", "checklist", .task).accessibilityIdentifier("makeMailTaskButton")
                row("Add Calendar Event", "calendar.badge.plus", .calendar)
                if !message.isDraft {
                    row("Add to collection", "folder.badge.plus", .collection).accessibilityIdentifier("addToCollectionButton")
                    row("Save receipt", "receipt", .receipt).accessibilityIdentifier("makeReceiptButton")
                }
            } footer: { Text("Reminders use Dispatch tasks. Print and PDF use a readable text copy. Forward as attachment includes the original message file.") }
            Section("Security") { row("Open Security Inspector", "checkmark.shield", .security) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Message actions").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { dismiss() } } }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func select(_ action: MessageSheetAction) { feedback.select(); choose(action) }
    private func row(_ title: String, _ symbol: String, _ action: MessageSheetAction, destructive: Bool = false) -> some View {
        Button(role: destructive ? .destructive : nil) { select(action) } label: { Label(title, systemImage: symbol) }.frame(minHeight: 32)
    }
    private func quick(_ title: String, _ symbol: String, _ action: MessageSheetAction) -> some View {
        Button { select(action) } label: {
            VStack(spacing: 8) { Image(systemName: symbol).font(.title2); Text(title).font(.subheadline) }
                .frame(maxWidth: .infinity, minHeight: 78)
        }.buttonStyle(.glass).accessibilityLabel(title)
    }
    private func unavailable(_ title: String, _ symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol); Spacer(); Text("Coming soon").font(.caption) }.foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
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
