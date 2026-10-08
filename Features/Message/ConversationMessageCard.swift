import SwiftUI

struct ConversationMessageCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MailFeedback.self) private var feedback
    let message: MailMessage
    let attachments: [MailAttachment]
    let remoteImages: Bool
    let onReply: () -> Void
    let onReplyAll: () -> Void
    let onForward: () -> Void
    let onSender: () -> Void
    let account: MailAccount?
    let onSecurity: () -> Void
    let onLoadImages: () -> Void
    @State private var expanded: Bool

    init(message: MailMessage, initiallyExpanded: Bool, attachments: [MailAttachment], remoteImages: Bool,
         onReply: @escaping () -> Void, onReplyAll: @escaping () -> Void, onForward: @escaping () -> Void,
         onSender: @escaping () -> Void, account: MailAccount? = nil, onSecurity: @escaping () -> Void = {}, onLoadImages: @escaping () -> Void = {}) {
        self.message = message; self.attachments = attachments; self.remoteImages = remoteImages
        self.onReply = onReply; self.onReplyAll = onReplyAll; self.onForward = onForward
        self.onSender = onSender
        self.account = account; self.onSecurity = onSecurity
        self.onLoadImages = onLoadImages
        _expanded = State(initialValue: initiallyExpanded)
    }
    private var bodyText: String {
        message.plainTextBody ?? message.snippet
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .top, spacing: 6) {
            Button {
                feedback.select()
                withAnimation(MailStyle.motion(reduced: reduceMotion)) { expanded.toggle() }
            } label: {
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
            Button { feedback.select(); onSecurity() } label: {
                Image(systemName: MailSecurityObservations.statusSymbol).font(.title3).frame(width: 44, height: 44)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Security Inspector, not analysed").accessibilityIdentifier("securityInspector-\(message.remoteID)")
          }
            if expanded {
                HStack(spacing: 8) {
                    Circle().fill(Color(mailHex: account?.colourHex ?? "007AFF")).frame(width: 7, height: 7)
                    Text(account?.email ?? "Account unavailable").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                }
                MessageRecipientDetails(message: message)
                if MailMIME.valid(message.senderEmail) {
                    Button("Sender profile", systemImage: "person.crop.rectangle") { onSender() }
                        .font(.subheadline).accessibilityIdentifier("openSenderProfile-\(message.remoteID)")
                }
                Divider().padding(.vertical, 2)
                if !remoteImages, let html = message.cachedHTML.flatMap({ String(data: $0, encoding: .utf8) }), MailMIME.hasRemoteImages(html) {
                    Button("Load External Images", systemImage: "photo") { feedback.select(); onLoadImages() }
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                        .background(MailStyle.tile, in: .rect(cornerRadius: 12))
                }
                MailBodyView(html: message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }, text: bodyText, remoteImages: remoteImages)
                    .accessibilityIdentifier("conversationBody-\(message.remoteID)")
                ForEach(attachments) { AttachmentRow(attachment: $0) }
                if !message.isDraft {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { replyButton; forwardButton; Spacer(minLength: 0); replyMenu }
                        VStack(alignment: .leading, spacing: 10) { replyButton; forwardButton; replyMenu }
                    }.padding(.top, 12)
                }
            }
        }
        .padding(.vertical, 18)
        .background(MailStyle.paper)
    }
    private var replyButton: some View {
        Button("Reply", systemImage: "arrowshape.turn.up.left") { feedback.select(); onReply() }
            .buttonStyle(.glassProminent).controlSize(.large)
    }
    private var forwardButton: some View {
        Button("Forward", systemImage: "arrowshape.turn.up.right") { feedback.select(); onForward() }
            .buttonStyle(.glass).controlSize(.large)
    }
    private var replyMenu: some View {
        Menu("More reply options", systemImage: "ellipsis") {
            Button("Reply all", systemImage: "arrowshape.turn.up.left.2") { feedback.select(); onReplyAll() }
            Button("Forward", systemImage: "arrowshape.turn.up.right") { feedback.select(); onForward() }
        }.accessibilityLabel("More reply options").frame(minWidth: 44, minHeight: 44)
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
