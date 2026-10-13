import SwiftUI

struct ConversationMessageCard: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(MailFeedback.self) private var feedback
    let message: MailMessage
    let attachments: [MailAttachment]
    let remoteImages: Bool
    let onSender: () -> Void
    let account: MailAccount?
    let onSecurity: () -> Void
    let onLoadImages: () -> Void
    let onFocus: () -> Void
    @State private var expanded: Bool

    init(message: MailMessage, initiallyExpanded: Bool, attachments: [MailAttachment], remoteImages: Bool,
         onSender: @escaping () -> Void, account: MailAccount? = nil, onSecurity: @escaping () -> Void = {}, onLoadImages: @escaping () -> Void = {}, onFocus: @escaping () -> Void = {}) {
        self.message = message; self.attachments = attachments; self.remoteImages = remoteImages
        self.onSender = onSender
        self.account = account; self.onSecurity = onSecurity
        self.onLoadImages = onLoadImages
        self.onFocus = onFocus
        _expanded = State(initialValue: initiallyExpanded)
    }
    private var bodyText: String {
        message.plainTextBody ?? message.snippet
    }
    private var securityVerdict: SecurityVerdict {
        guard let saved = runtime.securityReports[message.id], saved.fingerprint == MailSecurityContent.fingerprint(message, attachments: attachments) else { return .unknown }
        return saved.report.verdict
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 12) {
            Button { feedback.select(); onSender() } label: {
                SenderAvatar(email: message.senderEmail, name: message.sender.displayName, context: message.subject).frame(width: 44, height: 44).contentShape(.circle)
            }.buttonStyle(.plain).disabled(!MailMIME.valid(message.senderEmail))
                .accessibilityLabel("Show \(message.sender.displayName)’s contact sheet")
                .accessibilityIdentifier("openSenderProfile-\(message.remoteID)")
            Button {
                feedback.select()
                withAnimation(MailStyle.motion(reduced: reduceMotion)) { expanded.toggle(); if expanded { onFocus() } }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.sender.displayName).font(.headline).foregroundStyle(MailStyle.ink)
                        if !expanded { Text(message.snippet).font(.subheadline).foregroundStyle(MailStyle.secondaryInk).lineLimit(typeSize.isAccessibilitySize ? nil : 2) }
                        else { Text(message.receivedAt, format: .dateTime.day().month().hour().minute()).font(.footnote).foregroundStyle(MailStyle.secondaryInk) }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 6) {
                        if !expanded { MailRowDate(date: message.receivedAt) }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(MailStyle.secondaryInk)
                    }
                }.frame(minHeight: 44, alignment: .top).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conversationHeader-\(message.remoteID)")
            .accessibilityLabel("Message from \(message.sender.displayName), \(message.receivedAt.formatted())")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Collapse message" : "Expand message")
          }
            if expanded {
                MessageRecipientDetails(message: message, account: account)
                MailRule().padding(.vertical, 8)
                if !remoteImages, let html = message.cachedHTML.flatMap({ String(data: $0, encoding: .utf8) }), MailMIME.hasRemoteImages(html) {
                    Button("Load External Images", systemImage: "photo") { feedback.select(); onLoadImages() }
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                        .background(MailStyle.tile, in: .rect(cornerRadius: MailStyle.controlRadius))
                }
                MailBodyView(html: message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }, text: bodyText, remoteImages: remoteImages)
                    .accessibilityIdentifier("conversationBody-\(message.remoteID)")
                ForEach(attachments) { AttachmentRow(attachment: $0) }
            }
        }
        .padding(.vertical, 16)
        .background(MailStyle.paper)
        .overlay(alignment: .top) { MailRule() }
    }
}

private struct MessageRecipientDetails: View {
    let message: MailMessage
    let account: MailAccount?
    private var summary: String {
        guard let first = message.to.first else { return "Recipient details" }
        let others = message.to.count + message.cc.count - 1
        return "To: \(first.email)" + (others > 0 ? " and \(others) more" : "")
    }
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text("From: \(message.senderEmail)")
                Text("To: " + message.to.map { address in address.name.map { "\($0) <\(address.email)>" } ?? address.email }.joined(separator: ", "))
                if !message.cc.isEmpty { Text("Cc: " + message.cc.map(\.email).joined(separator: ", ")) }
                if !message.bcc.isEmpty { Text("Bcc: " + message.bcc.map(\.email).joined(separator: ", ")) }
                if !message.replyTo.isEmpty { Text("Reply to: " + message.replyTo.map(\.email).joined(separator: ", ")) }
                if let account { Text("Account: \(account.displayName) <\(account.email)>") }
                Text(message.receivedAt, format: .dateTime.day().month().year().hour().minute())
            }.textSelection(.enabled)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(account.map { Color(mailHex: $0.colourHex) } ?? MailStyle.secondaryInk).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(summary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.footnote).foregroundStyle(MailStyle.secondaryInk)
        .frame(minHeight: 44)
    }
}
