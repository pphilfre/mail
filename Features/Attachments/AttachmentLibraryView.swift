import SwiftUI
import SwiftData
import QuickLook

struct AttachmentLibraryView: View {
    let accountID: UUID?
    var onSelect: ((MailAttachment) -> Void)? = nil
    @Environment(AppSession.self) private var session
    @Query private var attachments: [MailAttachment]
    @Query private var messages: [MailMessage]
    @Query private var accounts: [MailAccount]
    private var entries: [AttachmentCatalogEntry] {
        let mail = Dictionary(uniqueKeysWithValues: messages.filter { !$0.isTrash && !$0.isSpam && !$0.isDraft }.map { ($0.id, $0) })
        let accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.email) })
        let received = attachments.compactMap { file -> AttachmentCatalogEntry? in
            guard let message = mail[file.messageID] else { return nil }
            return AttachmentCatalogEntry(id: "mail:\(file.id)", accountID: file.accountID, attachmentID: file.id,
                messageID: message.id, draftID: nil, filename: file.filename, mimeType: file.mimeType,
                byteCount: max(0, file.byteCount), sourceTitle: message.subject, correspondent: message.senderEmail,
                accountName: accountNames[file.accountID] ?? "", date: message.receivedAt,
                inlineImage: file.contentID != nil && file.mimeType.lowercased().hasPrefix("image/"), cachedPath: file.cachedRelativePath)
        }
        let local = session.drafts.flatMap { draft in
            draft.attachments.map { file in
                AttachmentCatalogEntry(id: "draft:\(draft.id):\(file.id)", accountID: draft.accountID,
                    attachmentID: file.id, messageID: nil, draftID: draft.id, filename: file.filename, mimeType: file.mimeType,
                    byteCount: max(0, file.byteCount), sourceTitle: draft.displaySubject, correspondent: draft.to,
                    accountName: draft.accountID.flatMap { accountNames[$0] } ?? "No account selected",
                    date: draft.updatedAt, inlineImage: false, cachedPath: nil)
            }
        }
        return onSelect == nil ? received + local : received
    }
    var body: some View {
        AttachmentLibraryResults(accountID: accountID, onSelect: onSelect, attachments: attachments,
            messages: messages, accounts: accounts, entries: entries)
    }
}

/// Query keystrokes update only the results; catalogue snapshots follow storage changes.
private struct AttachmentLibraryResults: View {

    let accountID: UUID?
    var onSelect: ((MailAttachment) -> Void)? = nil
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppSession.self) private var session
    let attachments: [MailAttachment]
    let messages: [MailMessage]
    let accounts: [MailAccount]
    let entries: [AttachmentCatalogEntry]
    @State private var recognizedText: [String: String] = [:]
    @State private var ocrError: String?
    @State private var query = ""
    @State private var category = AttachmentCategory.all
    @State private var sort = AttachmentSort.newest
    @State private var includeInline = false
    @State private var savedOnly = false
    @State private var savedIDs = Set<String>()
    @State private var checkingFiles = false
    @State private var editingDraft: LocalDraft?
    var body: some View {
        let snapshot = entries
        let searchable = snapshot.map { file in var value = file; value.recognizedText = recognizedText[file.id] ?? ""; return value }
        let files = AttachmentCatalogEntry.filtered(searchable, accountID: accountID, query: query, category: category,
            includeInline: includeInline, savedOnly: savedOnly, savedIDs: savedIDs, sort: sort)
        List {
            Section {
                if let ocrError { Text(ocrError).font(.caption).foregroundStyle(.secondary) }
                if checkingFiles { ProgressView().controlSize(.small).accessibilityLabel("Checking saved files") }
            }
            ForEach(files) { file in
                VStack(alignment: .leading, spacing: 10) {
                    if let messageID = file.messageID, let attachment = attachments.first(where: { $0.id == file.attachmentID }),
                       let message = messages.first(where: { $0.id == messageID }) {
                        HStack {
                            AttachmentRow(attachment: attachment)
                            if let onSelect {
                                Button { onSelect(attachment) } label: {
                                    Image(systemName: "plus.circle").frame(width: 44, height: 44)
                                }.accessibilityLabel("Attach " + file.filename)
                                    .accessibilityIdentifier("selectEmailAttachment-" + file.filename)
                            }
                        }
                        NavigationLink { GmailMessageView(message: message) } label: { Label(file.sourceTitle.isEmpty ? "Open original email" : file.sourceTitle, systemImage: "envelope") }
                            .font(.subheadline).accessibilityIdentifier("attachmentSource-\(file.filename)")
                    } else if let id = file.draftID, let draft = session.drafts.first(where: { $0.id == id }),
                              let attachment = draft.attachments.first(where: { $0.id == file.attachmentID }) {
                        DraftLibraryFileRow(draftID: id, attachment: attachment)
                        Button { editingDraft = draft } label: { Label("Draft: \(draft.displaySubject)", systemImage: "square.and.pencil") }
                            .font(.subheadline)
                    }
                    Text(file.correspondent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    HStack {
                        if accountID == nil { Text(file.accountName).lineLimit(1) }
                        Spacer()
                        Text(file.date, format: .dateTime.day().month(.abbreviated).year())
                    }.font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 7)
            }
            if files.isEmpty && !checkingFiles {
                ContentUnavailableView("No matching files", systemImage: "paperclip",
                    description: Text("Files from downloaded messages and saved drafts appear here. Try another filter or download more mail."))
            }
        }
        .modifier(MailWorkspaceList())
        .mailSheetTitle("Attachments")
        .searchable(text: $query, prompt: "Filename, sender or document text")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("Library options", systemImage: "line.3.horizontal.decrease") {
                    Picker("File type", selection: $category) {
                        ForEach(AttachmentCategory.allCases) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("attachmentCategoryPicker")
                    Toggle("Saved for offline use", isOn: $savedOnly).accessibilityIdentifier("attachmentSavedFilter")
                    Picker("Sort", selection: $sort) { ForEach(AttachmentSort.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Include inline images", isOn: $includeInline)
                }
            }
        }
        .sheet(item: $editingDraft) { draft in NavigationStack { ComposeView(draft: draft) } }
        .task(id: snapshot) {
            checkingFiles = true
            var available = Set<String>()
            let cache = runtime.gmail?.attachmentCache ?? AttachmentCache()
            for file in snapshot {
                guard !Task.isCancelled else { return }
                var url: URL?
                if let id = file.draftID, let draft = session.drafts.first(where: { $0.id == id }),
                   let item = draft.attachments.first(where: { $0.id == file.attachmentID }) {
                    url = try? await runtime.draftAttachments.preview(item, draftID: id)
                } else { url = try? await cache.existing(file.cachedPath) }
                if let url {
                    available.insert(file.id)
                    do { recognizedText[file.id] = try await AttachmentTextIndex.shared.text(at: url, id: file.id) }
                    catch { if !Task.isCancelled { ocrError = "Some document text could not be indexed: " + error.localizedDescription } }
                }
            }
            guard !Task.isCancelled else { return }
            savedIDs = available; checkingFiles = false
        }
    }
}

private struct DraftLibraryFileRow: View {
    let draftID: UUID
    let attachment: DraftAttachment
    @Environment(AppRuntime.self) private var runtime
    @State private var fileURL: URL?
    @State private var previewURL: URL?
    @State private var errorMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.filename).font(.subheadline).lineLimit(2)
                        Text(attachment.sizeDescription).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "doc").foregroundStyle(.secondary) }
                Spacer()
                if let fileURL {
                    Button("Preview") { previewURL = fileURL }.frame(minHeight: 44)
                    ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                        .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Share \(attachment.filename)")
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12).background(MailStyle.tile, in: .rect(cornerRadius: MailStyle.controlRadius))
        .buttonStyle(.borderless)
        .quickLookPreview($previewURL)
        .onDisappear { AttachmentPreviewStore.remove(fileURL); fileURL = nil; previewURL = nil }
        .task(id: attachment.id) {
            do { fileURL = try await runtime.draftAttachments.securePreview(attachment, draftID: draftID) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
