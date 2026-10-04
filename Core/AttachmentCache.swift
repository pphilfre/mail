import Foundation

enum AttachmentError: LocalizedError, Equatable {
    case tooLarge, unavailable, invalidPath
    var errorDescription: String? {
        switch self {
        case .tooLarge: "This attachment is larger than 25 MB. Open it in Gmail to download it."
        case .unavailable: "This attachment is no longer available. Refresh the message and try again."
        case .invalidPath: "The saved attachment could not be opened. Download it again."
        }
    }
}

/// File work stays off the main actor. Provider filenames never become directory paths.
actor AttachmentCache {
    static let maximumBytes = 25 * 1024 * 1024
    let root: URL
    init(root: URL = URL.applicationSupportDirectory.appending(path: "Mail/Attachments", directoryHint: .isDirectory)) {
        self.root = root
    }
    static func safeFilename(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:").union(.controlCharacters))
            .joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "Attachment" : String(cleaned.suffix(180))
    }
    private func url(_ relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/")
        guard !relativePath.hasPrefix("/"), !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw AttachmentError.invalidPath }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = canonicalRoot.path + "/"
        var candidate = canonicalRoot
        // Resolve existing parents individually, even when the final file does not exist yet.
        for component in components {
            candidate = candidate.appending(path: String(component)).standardizedFileURL.resolvingSymlinksInPath()
            guard candidate.path.hasPrefix(prefix) else { throw AttachmentError.invalidPath }
        }
        return candidate
    }
    func existing(_ relativePath: String?) throws -> URL? {
        guard let relativePath else { return nil }
        let file = try url(relativePath)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }
    func store(_ data: Data, accountID: UUID, attachmentID: UUID, filename: String) throws -> String {
        guard data.count <= Self.maximumBytes else { throw AttachmentError.tooLarge }
        let path = "\(accountID.uuidString)/\(attachmentID.uuidString)/\(Self.safeFilename(filename))"
        let file = try url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        var directory = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return path
    }
    func removeAccount(_ id: UUID) throws {
        let directory = try url(id.uuidString)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func prune(keeping paths: Set<String>) throws {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let file as URL in enumerator {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            // Keep recent writes in case another storage open overlaps an in-flight download.
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            if !paths.contains(relative) && modified < Date().addingTimeInterval(-86400) { try FileManager.default.removeItem(at: try url(relative)) }
        }
    }
}
