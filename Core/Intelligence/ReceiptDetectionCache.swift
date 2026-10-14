import Foundation
import CryptoKit

/// Saves positive and negative detections; downloaded or edited bodies invalidate only their entry.
actor ReceiptDetectionCache {
    static let shared = ReceiptDetectionCache()
    private struct Entry: Codable {
        let fingerprint: String
        let receipt: ReceiptSummary?
        let updated: Date
    }
    private let root: URL
    private var entries: [String: Entry] = [:]
    private var loaded = false
    init(root: URL = URL.applicationSupportDirectory.appending(path: "Dispatch/Receipts")) { self.root = root }

    private func fingerprint(_ source: ReceiptSource) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(source)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func receipts(for sources: [ReceiptSource]) -> [ReceiptSummary] {
        let file = root.appending(path: "detections-v1.json")
        if !loaded {
            if let data = try? Data(contentsOf: file),
               let saved = try? JSONDecoder().decode([String: Entry].self, from: data) { entries = saved }
            loaded = true
        }
        var result: [ReceiptSummary] = []
        var changed = false
        for source in sources {
            guard !Task.isCancelled else { return [] }
            let key = source.id.uuidString
            let hash = fingerprint(source)
            let entry: Entry
            if let saved = entries[key], saved.fingerprint == hash { entry = saved }
            else {
                entry = Entry(fingerprint: hash, receipt: ReceiptDetector.detect(source), updated: Date())
                entries[key] = entry
                changed = true
            }
            if let receipt = entry.receipt { result.append(receipt) }
        }
        if changed && !Task.isCancelled {
            if entries.count > 5_000 {
                entries = Dictionary(uniqueKeysWithValues: entries.sorted { $0.value.updated > $1.value.updated }.prefix(5_000).map { ($0.key, $0.value) })
            }
            do {
                try LocalMailProtection.protectDirectory(root)
                try JSONEncoder().encode(entries).write(to: file, options: [.atomic, .completeFileProtection])
            } catch { /* Disposable cache: mail remains available when persistence fails. */ }
        }
        return result
    }
}
