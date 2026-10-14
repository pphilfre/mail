import Foundation
import CryptoKit

/// Content-addressed, protected local summaries. Read flags and UI state do not invalidate them.
actor MailSummaryCache {
    static let shared = MailSummaryCache()
    private let root: URL
    private var memory: [String: MailSummaryResult] = [:]
    init(root: URL = URL.applicationSupportDirectory.appending(path: "Dispatch/Summaries")) { self.root = root }
    static func key(_ sources: [MailSummarySource]) -> String {
        var hash = SHA256()
        // Length framing prevents different field boundaries from producing the same input.
        for source in sources {
            for field in [source.sender, source.subject, source.text ?? "", source.html ?? "", source.reader ?? ""] {
                hash.update(data: Data("\(field.utf8.count):".utf8))
                hash.update(data: Data(field.utf8))
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func value(for sources: [MailSummarySource]) -> MailSummaryResult? {
        let key = Self.key(sources)
        if let result = memory[key] { return result }
        guard let data = try? Data(contentsOf: root.appending(path: key + ".json")),
              let result = try? JSONDecoder().decode(MailSummaryResult.self, from: data), result.generated else { return nil }
        remember(result, key: key)
        return result
    }
    func store(_ result: MailSummaryResult, for sources: [MailSummarySource]) {
        guard result.generated, result.missingBodies == 0, !result.text.isEmpty else { return }
        let key = Self.key(sources)
        remember(result, key: key)
        do {
            try LocalMailProtection.protectDirectory(root)
            var directory = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try JSONEncoder().encode(result).write(to: root.appending(path: key + ".json"), options: [.atomic, .completeFileProtection])
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "json" }
                .sorted {
                    let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return lhs > rhs
                }
            for file in files.dropFirst(100) { try? FileManager.default.removeItem(at: file) }
        } catch { /* A disposable cache must never prevent reading mail. */ }
    }
    func clear() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: root)
    }
    private func remember(_ result: MailSummaryResult, key: String) {
        if memory.count >= 100 { memory.removeAll(keepingCapacity: true) }
        memory[key] = result
    }
}
