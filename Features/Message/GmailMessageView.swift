import SwiftUI
import SwiftData

struct GmailMessageView: View {
    let message: MailMessage
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MailMessage.receivedAt) private var allMessages: [MailMessage]
    @Query private var attachments: [MailAttachment]
    @Query private var accounts: [MailAccount]
    @Query(sort: \MailFolder.name) private var folders: [MailFolder]
    @AppStorage("remoteImages") private var remoteImages = false
    @State private var loadImagesOnce = false
    @State private var composing: LocalDraft?
    @State private var localError: String?
    private var thread: [MailMessage] { allMessages.filter { $0.accountID == message.accountID && $0.remoteThreadID == message.remoteThreadID } }
    private func bodyText(_ row: MailMessage) -> String {
        row.plainTextBody ?? row.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }.map(MailMIME.readableHTML) ?? row.snippet
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(message.subject.isEmpty ? "No subject" : message.subject).font(.title2.bold())
                if !remoteImages && !loadImagesOnce && thread.contains(where: { $0.cachedHTML != nil }) {
                    HStack {
                        Label("Remote images are off", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Load images") { loadImagesOnce = true }.font(.caption.bold())
                    }
                }
                ForEach(thread) { row in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SenderAvatar(email: row.senderEmail, name: row.sender.displayName)
                            VStack(alignment: .leading) {
                                Text(row.sender.displayName).font(.headline)
                                Text(row.senderEmail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.receivedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("To: " + row.to.map(\.email).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        if !row.cc.isEmpty { Text("Cc: " + row.cc.map(\.email).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                        MailBodyView(html: row.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }, text: bodyText(row), remoteImages: remoteImages || loadImagesOnce)
                            .padding(.horizontal, -16)
                        ForEach(attachments.filter { $0.messageID == row.id }) { attachment in
                            Label("\(attachment.filename) · \(attachment.byteCount.formatted()) bytes", systemImage: "paperclip").font(.caption)
                        }
                        if attachments.contains(where: { $0.messageID == row.id }) { Text("Attachment download is coming in the reader stage.").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Reply") { reply(row, all: false) }
                            Button("Reply all") { reply(row, all: true) }
                            Button("Forward") { forward(row) }
                        }.buttonStyle(.bordered)
                        Divider()
                    }
                }
                if message.isDraft {
                    Button("Edit Gmail draft") {
                        Task {
                            do {
                                guard let gmail = runtime.gmail else { return }
                                composing = try await gmail.importDraft(message)
                                try session.reloadDrafts()
                            } catch { localError = error.localizedDescription }
                        }
                    }
                    Button("Delete Gmail draft", role: .destructive) {
                        Task {
                            do {
                                guard let gmail = runtime.gmail else { return }
                                let draft = try await gmail.importDraft(message)
                                if let id = try runtime.repository?.outgoing(draft.id)?.remoteDraftID {
                                    try await gmail.client(message.accountID).deleteDraft(id)
                                    if let row = try runtime.repository?.outgoing(draft.id) { runtime.repository?.context.delete(row); try runtime.repository?.context.save() }
                                    try session.reloadDrafts(); await gmail.sync(message.accountID); dismiss()
                                }
                            } catch { localError = error.localizedDescription }
                        }
                    }
                }
                if let error = localError ?? runtime.gmail?.error { Text(error).foregroundStyle(.red) }

            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Message").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(message.isStarred ? "Unstar" : "Star", systemImage: message.isStarred ? "star.fill" : "star") {
                    runtime.gmail?.action(message.isStarred ? "unstar" : "star", message: message)
                }
                Menu("More", systemImage: "ellipsis.circle") {
                    Button(message.isRead ? "Mark unread" : "Mark read") { runtime.gmail?.action(message.isRead ? "unread" : "read", message: message) }
                    Button("Archive", systemImage: "archivebox") { runtime.gmail?.action("archive", message: message); dismiss() }
                    Button(message.isTrash ? "Restore" : "Move to Trash", systemImage: "trash") {
                        runtime.gmail?.action(message.isTrash ? "restore" : "trash", message: message); dismiss()
                    }
                    Menu("Labels") {
                        ForEach(folders.filter { $0.accountID == message.accountID && $0.kindRaw == "user" }) { folder in
                            Button {
                                runtime.gmail?.action((message.folderIDs.contains(folder.remoteID) ? "labelRemove:" : "labelAdd:") + folder.remoteID, message: message)
                            } label: {
                                Label(folder.name, systemImage: message.folderIDs.contains(folder.remoteID) ? "checkmark" : "tag")
                            }
                        }
                    }
                }
            }
        }
        .task {
            if !message.isRead { runtime.gmail?.action("read", message: message) }
            await runtime.gmail?.loadThread(message)
        }
        .sheet(item: $composing) { draft in NavigationStack { ComposeView(draft: draft) } }
    }
    private func reply(_ row: MailMessage, all: Bool) {
        let own = accounts.first { $0.id == row.accountID }?.email.lowercased() ?? ""
        let recipients = MailReplyRecipients.make(sender: row.sender, replyTo: row.replyTo, to: row.to, cc: row.cc,
            ownEmail: own, replyAll: all)
        let references = [row.referencesHeader, row.internetMessageID].compactMap { $0 }.joined(separator: " ")
        composing = LocalDraft(to: recipients.to.joined(separator: ", "), cc: recipients.cc.joined(separator: ", "), subject: row.subject,
            body: "\n\nOn \(row.receivedAt.formatted()), \(row.sender.displayName) wrote:\n" + bodyText(row).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n"),
            accountID: row.accountID, remoteThreadID: row.internetMessageID == nil ? nil : row.remoteThreadID,
            inReplyTo: row.internetMessageID, referencesHeader: references.isEmpty ? nil : references)
    }
    private func forward(_ row: MailMessage) {
        composing = LocalDraft(subject: "Fwd: " + row.subject,
            body: "\n\nForwarded message\nFrom: \(row.senderEmail)\nDate: \(row.receivedAt.formatted())\nSubject: \(row.subject)\n\n" + bodyText(row), accountID: row.accountID)
        if attachments.contains(where: { $0.messageID == row.id }) { localError = "This forward contains message text only. Attachments are not included yet." }
    }
}
