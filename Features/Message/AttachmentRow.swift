import SwiftUI
import QuickLook

struct AttachmentRow: View {
    let attachment: MailAttachment
    @Environment(AppRuntime.self) private var runtime
    @State private var fileURL: URL?
    @State private var previewURL: URL?
    @State private var loading = false
    @State private var errorMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename).font(.subheadline).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if loading { ProgressView().accessibilityLabel("Downloading attachment") }
                else if let fileURL {
                    Button("Preview") { previewURL = fileURL }
                    ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share or save \(attachment.filename)")
                } else {
                    Button("Download", systemImage: "arrow.down.circle") { Task { await download() } }
                        .labelStyle(.iconOnly).accessibilityLabel("Download \(attachment.filename)")
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .quickLookPreview($previewURL)
        .task(id: attachment.cachedRelativePath) {
            fileURL = try? await runtime.gmail?.attachmentCache.existing(attachment.cachedRelativePath)
        }
    }
    private func download() async {
        guard !loading, let gmail = runtime.gmail else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do { fileURL = try await gmail.download(attachment); previewURL = fileURL }
        catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
}
