import Foundation
import CryptoKit
import UniformTypeIdentifiers

struct DraftAttachment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let byteCount: Int
    let sha256: String
    var sizeDescription: String { ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file) }
}

enum ComposeAttachmentError: LocalizedError, Equatable {
    case tooLarge, tooMany, unavailable, invalidFile
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Keep attachments under 20 MB in total. Remove a file or choose a smaller copy."
        case .tooMany: "You can attach up to 20 files to a message."
        case .unavailable: "An attached file is missing or changed. Remove it and attach it again before sending."
        case .invalidFile: "Choose a file rather than a folder."
        }
    }
}

/// Originals are copied before selection access ends. Files remain available for discard,
/// relaunch and uncertain-send recovery; manifests live in existing SwiftData metadata.
actor DraftAttachmentStore {
    static let maximumBytes = 20 * 1024 * 1024
    static let maximumCount = 20
    let root: URL
    init(root: URL = URL.applicationSupportDirectory.appending(path: "Dispatch/DraftAttachments", directoryHint: .isDirectory)) {
        self.root = root
    }
    static func validate(_ attachments: [DraftAttachment]) throws {
        guard attachments.count <= maximumCount else { throw ComposeAttachmentError.tooMany }
        var total = 0
        for item in attachments {
            guard item.byteCount >= 0, item.byteCount <= maximumBytes - total else { throw ComposeAttachmentError.tooLarge }
            total += item.byteCount
        }
        guard Set(attachments.map(\.id)).count == attachments.count else { throw ComposeAttachmentError.invalidFile }
    }
    private func url(draftID: UUID, attachment: DraftAttachment) throws -> URL {
        guard attachment.filename == AttachmentCache.safeFilename(attachment.filename) else { throw ComposeAttachmentError.invalidFile }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var file = canonicalRoot
        for component in [draftID.uuidString, attachment.id.uuidString, attachment.filename] {
            file = file.appending(path: component).standardizedFileURL.resolvingSymlinksInPath()
            guard file.path.hasPrefix(canonicalRoot.path + "/") else { throw ComposeAttachmentError.invalidFile }
        }
        return file
    }
    func store(_ data: Data, filename: String, mimeType: String, draftID: UUID, existing: [DraftAttachment]) throws -> DraftAttachment {
        let item = DraftAttachment(id: UUID(), filename: AttachmentCache.safeFilename(filename),
            mimeType: mimeType, byteCount: data.count, sha256: Self.digest(data))
        try Self.validate(existing + [item])
        let file = try url(draftID: draftID, attachment: item)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        return item
    }
    func importFile(_ source: URL, draftID: UUID, existing: [DraftAttachment]) throws -> DraftAttachment {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true else { throw ComposeAttachmentError.invalidFile }
        guard (values.fileSize ?? 0) <= Self.maximumBytes else { throw ComposeAttachmentError.tooLarge }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        return try store(data, filename: source.lastPathComponent,
            mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream", draftID: draftID, existing: existing)
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func preview(_ attachment: DraftAttachment, draftID: UUID) throws -> URL {
        let file = try url(draftID: draftID, attachment: attachment)
        guard FileManager.default.fileExists(atPath: file.path) else { throw ComposeAttachmentError.unavailable }
        return file
    }
    func raw(_ draft: LocalDraft, from: String, requireRecipient: Bool = true) throws -> String {
        try Self.validate(draft.attachments)
        let files = try draft.attachments.map { attachment in
            let file = try preview(attachment, draftID: draft.id)
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard data.count == attachment.byteCount, Self.digest(data) == attachment.sha256 else { throw ComposeAttachmentError.unavailable }
            return MailMIME.OutgoingAttachment(filename: attachment.filename, mimeType: attachment.mimeType, data: data)
        }
        return try MailMIME.raw(draft, from: from, requireRecipient: requireRecipient, attachments: files)
    }
    func prune(keeping draftIDs: Set<UUID>, now: Date = Date()) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) {
            guard let id = UUID(uuidString: directory.lastPathComponent), !draftIDs.contains(id) else { continue }
            let canonical = directory.standardizedFileURL.resolvingSymlinksInPath()
            guard canonical.path.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { continue }
            let modified = try directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? now
            if modified < now.addingTimeInterval(-86400) { try FileManager.default.removeItem(at: canonical) }
        }
    }
}
