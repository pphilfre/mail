import Foundation

enum AttachmentCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All", documents = "Documents", images = "Images", archives = "Archives", other = "Other"
    var id: String { rawValue }
    static func classify(filename: String, mimeType: String) -> Self {
        let type = mimeType.lowercased(), ext = (filename as NSString).pathExtension.lowercased()
        if type.hasPrefix("image/") || ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "svg"].contains(ext) { return .images }
        if ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"].contains(ext) || ["application/zip", "application/x-7z-compressed", "application/x-rar-compressed"].contains(type) { return .archives }
        if type.hasPrefix("text/") || type == "application/pdf" || type.contains("officedocument") || type.contains("opendocument") ||
            ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "txt", "rtf", "odt", "ods", "odp", "ics"].contains(ext) { return .documents }
        return .other
    }
}

enum AttachmentSort: String, CaseIterable, Identifiable, Sendable {
    case newest = "Newest", largest = "Largest", name = "Name"
    var id: String { rawValue }
}

struct AttachmentCatalogEntry: Identifiable, Equatable, Sendable {
    let id: String
    let accountID: UUID?
    let attachmentID: UUID
    let messageID: UUID?
    let draftID: UUID?
    let filename: String
    let mimeType: String
    let byteCount: Int
    let sourceTitle: String
    let correspondent: String
    let accountName: String
    let date: Date
    let inlineImage: Bool
    let cachedPath: String?
    var recognizedText = ""
    var category: AttachmentCategory { AttachmentCategory.classify(filename: filename, mimeType: mimeType) }
    static func filtered(_ entries: [Self], accountID: UUID?, query: String, category: AttachmentCategory,
                         includeInline: Bool, savedOnly: Bool, savedIDs: Set<String>, sort: AttachmentSort) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter {
            (accountID == nil || $0.accountID == accountID) && (includeInline || !$0.inlineImage) &&
            (category == .all || $0.category == category) && (!savedOnly || savedIDs.contains($0.id)) &&
            (query.isEmpty || [$0.filename, $0.sourceTitle, $0.correspondent, $0.accountName, $0.recognizedText].contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { first, second in
            switch sort {
            case .newest: if first.date != second.date { return first.date > second.date }
            case .largest: if first.byteCount != second.byteCount { return first.byteCount > second.byteCount }
            case .name:
                let order = first.filename.localizedStandardCompare(second.filename)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return first.id < second.id
        }
    }
}
