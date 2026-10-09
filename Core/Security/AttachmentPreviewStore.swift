import Foundation

enum AttachmentPreviewError: LocalizedError {
    case blocked(String)
    var errorDescription: String? {
        switch self { case .blocked(let reason): "Preview unavailable. " + reason }
    }
}

enum AttachmentPreviewStore {
    static var root: URL { URL.applicationSupportDirectory.appending(path: "Dispatch/SecurityPreviews", directoryHint: .isDirectory) }
    static func write(_ data: Data, filename: String) throws -> URL {
        let directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try LocalMailProtection.protectDirectory(root)
        try LocalMailProtection.protectDirectory(directory)
        let file = directory.appending(path: AttachmentCache.safeFilename(filename))
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        try LocalMailProtection.protect(file)
        return file
    }
    static func remove(_ file: URL?) {
        guard let file else { return }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let directory = file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        guard directory.path.hasPrefix(canonicalRoot), UUID(uuidString: directory.lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: directory)
    }
    static func cleanExpired(now: Date = Date()) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for directory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey]) {
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
            let date = try directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? now
            if date < now.addingTimeInterval(-3600) { remove(directory.appending(path: "preview")) }
        }
    }
}
