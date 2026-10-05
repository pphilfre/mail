import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct ComposeAttachmentsView: View {
    let draftID: UUID
    @Binding var attachments: [DraftAttachment]
    @Binding var importing: Bool
    let onError: (String) -> Void
    @Environment(AppRuntime.self) private var runtime
    @State private var choosingFiles = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var previewURL: URL?
    private var remaining: Int { max(1, DraftAttachmentStore.maximumCount - attachments.count) }
    private var totalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(attachments.reduce(0) { $0 + $1.byteCount }), countStyle: .file)
    }

    var body: some View {
        Section {
            HStack {
                Button("Files", systemImage: "paperclip") { choosingFiles = true }
                    .accessibilityIdentifier("attachFileButton")
                Spacer()
                PhotosPicker(selection: $photos, maxSelectionCount: remaining, matching: .images, preferredItemEncoding: .current) {
                    Label("Photos", systemImage: "photo")
                }.accessibilityIdentifier("attachPhotoButton")
            }.disabled(attachments.count >= DraftAttachmentStore.maximumCount || importing)
            ForEach(attachments) { file in
                HStack {
                    Button {
                        Task {
                            do { previewURL = try await runtime.draftAttachments.preview(file, draftID: draftID) }
                            catch { onError(error.localizedDescription) }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.filename).foregroundStyle(.primary).lineLimit(2)
                                Text(file.sizeDescription).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "doc") }
                    }.accessibilityLabel("Preview \(file.filename), \(file.sizeDescription)")
                    Spacer()
                    Button {
                        attachments.removeAll { $0.id == file.id }
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Remove \(file.filename)")
                        .accessibilityIdentifier("removeAttachment-\(file.filename)")
                }.buttonStyle(.borderless)
            }
            if importing { ProgressView("Copying attachments…").accessibilityIdentifier("attachmentImportProgress") }
        } header: { Text(attachments.isEmpty ? "Attachments" : "Attachments · \(totalSize)") }
        footer: { Text("Up to 20 files and 20 MB total. Attached files are saved with your draft.") }
        .quickLookPreview($previewURL)
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let error): onError(error.localizedDescription)
            case .success(let files):
                importing = true
                Task { @MainActor in
                    defer { importing = false }
                    for file in files {
                        do {
                            let item = try await runtime.draftAttachments.importFile(file, draftID: draftID, existing: attachments)
                            attachments.append(item)
                        } catch { onError("\(file.lastPathComponent): \(error.localizedDescription)"); break }
                    }
                }
            }
        }
        .onChange(of: photos) { _, selection in
            guard !selection.isEmpty, !importing else { return }
            importing = true
            Task { @MainActor in
                defer { importing = false; photos = [] }
                for photo in selection {
                    do {
                        guard let data = try await photo.loadTransferable(type: Data.self) else { throw ComposeAttachmentError.unavailable }
                        let type = photo.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
                        let name = "Photo-\(UUID().uuidString.prefix(8)).\(type.preferredFilenameExtension ?? "jpg")"
                        let item = try await runtime.draftAttachments.store(data, filename: name,
                            mimeType: type.preferredMIMEType ?? "application/octet-stream", draftID: draftID, existing: attachments)
                        attachments.append(item)
                    } catch { onError(error.localizedDescription); break }
                }
            }
        }
    }
}
