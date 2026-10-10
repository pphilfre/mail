import SwiftUI

struct SecurityInspectorView: View {
    let message: MailMessage
    let attachments: [MailAttachment]
    var imagesAllowed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRuntime.self) private var runtime
    @AppStorage("remoteImages") private var remoteImages = false
    @State private var hashes: [UUID: String] = [:]
    private var observations: MailSecurityObservations {
        MailSecurityObservations(html: message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) } ?? "", text: message.plainTextBody ?? message.snippet)
    }
    var body: some View {
        List {
            Section {
                Label("Not analysed", systemImage: MailSecurityObservations.statusSymbol).font(.title3.weight(.semibold))
                Text("A question mark means there is no verified security verdict for this message.").foregroundStyle(.secondary)
            }
            Section("Authentication & identity") {
                ForEach(["SPF", "DKIM", "DMARC"], id: \.self) { LabeledContent($0, value: "Not analysed") }
                LabeledContent("Sender", value: message.senderEmail).textSelection(.enabled)
                Text("Trusted authentication results are not available in the cached message. A sender name or avatar does not verify identity.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Phishing & impersonation") {
                LabeledContent("Detection", value: "Not analysed")
                Text("Compare the sender’s full address with the organisation you expect before sharing information.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Links & redirects") {
                if observations.links.isEmpty { Text("No web links found in cached content.").foregroundStyle(.secondary) }
                ForEach(observations.links) { link in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(link.host).font(.subheadline.weight(.medium))
                        Text(link.destination).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        ForEach(link.concerns, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    }
                }
                Text("Links are listed without opening them. Redirects have not been followed. These observations do not determine whether a link is safe.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Attachments & SHA-256") {
                if attachments.isEmpty { Text("No attachments.").foregroundStyle(.secondary) }
                ForEach(attachments) { file in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(file.filename, systemImage: "doc")
                        Text("Safety: Not analysed").font(.caption).foregroundStyle(.secondary)
                        Text(hashes[file.id] ?? "SHA-256: Download the file to calculate its hash.")
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Text("A hash identifies file contents; it is not a safety verdict.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Tracking & privacy") {
                LabeledContent("External images", value: observations.hasRemoteImages ? "Found in cached HTML" : "None detected")
                LabeledContent("Image loading", value: imagesAllowed || remoteImages ? "Allowed for this reader" : "Blocked")
                LabeledContent("Possible tracking pixels", value: "\(observations.possibleTrackingPixels)")
                Text("Pixel detection checks small image dimensions only and may miss trackers. Loading external images can reveal that you opened a message.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("VirusTotal") {
                LabeledContent("File reputation", value: "Not analysed")
                LabeledContent("URL reputation", value: "Not analysed")
                Text("Coming soon. No files, hashes or URLs are sent to VirusTotal.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Security Inspector").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { dismiss() } } }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .task(id: attachments.map(\.cachedRelativePath)) {
            guard let cache = runtime.gmail?.attachmentCache else { return }
            for file in attachments {
                if let digest = try? await cache.sha256(file.cachedRelativePath) { hashes[file.id] = digest }
            }
        }
    }
}
