import SwiftUI

struct ConversationMessageCard: View {
    let message: MailMessage
    let attachments: [MailAttachment]
    let remoteImages: Bool
    let onReply: () -> Void
    let onReplyAll: () -> Void
    let onForward: () -> Void
    @State private var expanded: Bool

    init(message: MailMessage, initiallyExpanded: Bool, attachments: [MailAttachment], remoteImages: Bool,
         onReply: @escaping () -> Void, onReplyAll: @escaping () -> Void, onForward: @escaping () -> Void) {
        self.message = message; self.attachments = attachments; self.remoteImages = remoteImages
        self.onReply = onReply; self.onReplyAll = onReplyAll; self.onForward = onForward
        _expanded = State(initialValue: initiallyExpanded)
    }
    private var bodyText: String {
        message.plainTextBody ?? message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }.map(MailMIME.readableHTML) ?? message.snippet
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .top, spacing: 10) {
                    SenderAvatar(email: message.senderEmail, name: message.sender.displayName)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.sender.displayName).font(.headline).foregroundStyle(.primary)
                        Text(expanded ? message.senderEmail : message.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 6) {
                        MailRowDate(date: message.receivedAt)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conversationHeader-\(message.remoteID)")
            .accessibilityLabel("Message from \(message.sender.displayName), \(message.receivedAt.formatted())")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Collapse message" : "Expand message")
            if expanded {
                MessageRecipientDetails(message: message)
                MailBodyView(html: message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }, text: bodyText, remoteImages: remoteImages)
                    .accessibilityIdentifier("conversationBody-\(message.remoteID)")
                ForEach(attachments) { AttachmentRow(attachment: $0) }
                if !message.isDraft {
                    HStack {
                        Button("Reply", systemImage: "arrowshape.turn.up.left", action: onReply).buttonStyle(.bordered)
                        Menu("More reply options", systemImage: "ellipsis") {
                            Button("Reply all", systemImage: "arrowshape.turn.up.left.2", action: onReplyAll)
                            Button("Forward", systemImage: "arrowshape.turn.up.right", action: onForward)
                        }.accessibilityLabel("More reply options")
                    }
                }
            }
            Divider()
        }
    }
}

private struct MessageRecipientDetails: View {
    let message: MailMessage
    private var summary: String {
        guard let first = message.to.first else { return "Recipient details" }
        let others = message.to.count + message.cc.count - 1
        return "To \(first.displayName)" + (others > 0 ? " and \(others) more" : "")
    }
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("From: \(message.senderEmail)")
                Text("To: " + message.to.map { address in address.name.map { "\($0) <\(address.email)>" } ?? address.email }.joined(separator: ", "))
                if !message.cc.isEmpty { Text("Cc: " + message.cc.map(\.email).joined(separator: ", ")) }
                Text(message.receivedAt, format: .dateTime.day().month().year().hour().minute())
            }.textSelection(.enabled)
        } label: { Text(summary).lineLimit(2) }
        .font(.caption).foregroundStyle(.secondary)
    }
}
