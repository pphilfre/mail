import SwiftUI
import QuickLook

struct SavedOutgoingAttachmentsView: View {
    let outgoingID: UUID
    @Environment(AppRuntime.self) private var runtime
    @State private var files: [DraftAttachment] = []
    @State private var previewURL: URL?
    @State private var errorMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(files) { file in
                Button {
                    Task {
                        do { previewURL = try await runtime.draftAttachments.preview(file, draftID: outgoingID) }
                        catch { errorMessage = error.localizedDescription }
                    }
                } label: { Label("\(file.filename) · \(file.sizeDescription)", systemImage: "paperclip") }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.secondary) }
        }
        .quickLookPreview($previewURL)
        .task(id: outgoingID) {
            do {
                if let repository = runtime.repository, let row = try repository.outgoing(outgoingID) {
                    files = try repository.localDraft(row).attachments
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
