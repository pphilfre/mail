import Foundation

struct GmailProfile: Decodable, Sendable { let emailAddress: String; let historyId: String }
struct GmailReference: Codable, Sendable { let id: String; let threadId: String? }
struct GmailMessagePage: Decodable, Sendable { var messages: [GmailReference]?; var nextPageToken: String? }
struct GmailHeader: Codable, Sendable { let name: String; let value: String }
struct GmailBody: Codable, Sendable { var attachmentId: String?; var size: Int?; var data: String? }
struct GmailPart: Codable, Sendable {
    var partId: String?; var mimeType: String?; var filename: String?
    var headers: [GmailHeader]?; var body: GmailBody?; var parts: [GmailPart]?
    func header(_ name: String) -> String? {
        headers?.first { $0.name.lowercased() == name.lowercased() }?.value
            .replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
}
struct GmailMessageDTO: Codable, Sendable {
    let id: String
    let threadId: String
    var labelIds: [String]?
    var snippet: String?
    var internalDate: String?
    var payload: GmailPart?
}
struct GmailThreadDTO: Decodable, Sendable { let id: String; var messages: [GmailMessageDTO]? }
struct GmailLabel: Decodable, Sendable { let id: String; let name: String; var type: String? }
struct GmailLabelPage: Decodable, Sendable { var labels: [GmailLabel]? }
struct GmailDraftDTO: Codable, Sendable { let id: String; var message: GmailMessageDTO? }
struct GmailDraftPage: Decodable, Sendable { var drafts: [GmailDraftDTO]?; var nextPageToken: String? }
struct GmailHistoryChange: Decodable, Sendable { let message: GmailReference; var labelIds: [String]? }
struct GmailHistory: Decodable, Sendable {
    var messagesAdded: [GmailHistoryChange]?
    var messagesDeleted: [GmailHistoryChange]?
    var labelsAdded: [GmailHistoryChange]?
    var labelsRemoved: [GmailHistoryChange]?
}
struct GmailHistoryPage: Decodable, Sendable {
    var history: [GmailHistory]?
    var nextPageToken: String?
    let historyId: String
    var changedIDs: Set<String> {
        var result: Set<String> = []
        for record in history ?? [] {
            for change in record.messagesAdded ?? [] { result.insert(change.message.id) }
            for change in record.labelsAdded ?? [] { result.insert(change.message.id) }
            for change in record.labelsRemoved ?? [] { result.insert(change.message.id) }
        }
        return result
    }
    var deletedIDs: Set<String> { Set((history ?? []).flatMap { $0.messagesDeleted ?? [] }.map(\.message.id)) }
}

/// Only value types cross this actor boundary. Errors omit server bodies and tokens.
actor GmailAPI {
    let transport: any MailHTTPTransport
    let token: @Sendable (Bool) async throws -> String
    let pause: @Sendable (TimeInterval) async throws -> Void
    let onWait: @Sendable (TimeInterval?) async -> Void
    // An actor alone does not serialize requests across awaits. All endpoints,
    // including readers and mutations, share one account's request budget.
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var schedule = GmailRequestSchedule()
    init(transport: any MailHTTPTransport, pause: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }, onWait: @escaping @Sendable (TimeInterval?) async -> Void = { _ in }, token: @escaping @Sendable (Bool) async throws -> String) {
        self.transport = transport; self.token = token
        self.pause = pause; self.onWait = onWait
    }
    private func acquire() async {
        if !occupied { occupied = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { occupied = false }
        else { waiters.removeFirst().resume() }
    }
    private func request(_ path: String, method: String = "GET", query: [String: String] = [:], body: Data? = nil) async throws -> Data {
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        var url = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path)!
        url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!)
        request.httpMethod = method; request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        var refreshed = false
        var retries = 0
        request.setValue("Bearer " + (try await token(false)), forHTTPHeaderField: "Authorization")
        while true {
            try Task.checkCancellation()
            let delay = schedule.delay(at: ProcessInfo.processInfo.systemUptime)
            if delay > 0 {
                if schedule.isCoolingDown(at: ProcessInfo.processInfo.systemUptime) { await onWait(delay) }
                do { try await pause(delay) }
                catch { await onWait(nil); throw error }
                await onWait(nil)
            }
            try Task.checkCancellation()
            schedule.record(cost: Self.quotaCost(path, method: method), at: ProcessInfo.processInfo.systemUptime)
            let reply = try await transport.execute(request)
            if reply.status == 401 && !refreshed {
                refreshed = true
                request.setValue("Bearer " + (try await token(true)), forHTTPHeaderField: "Authorization")
                continue
            }
            let reason = reply.status == 403 ? Self.errorReason(reply.data) : "forbidden"
            let throttled = reply.status == 429 || (reply.status == 403 && ["rateLimitExceeded", "userRateLimitExceeded", "RATE_LIMIT_EXCEEDED"].contains(reason))
            if throttled || (500...599).contains(reply.status) {
                let backoff = pow(2, Double(retries)) + Double.random(in: 0...0.5)
                // Retry-After is a minimum, including values beyond 60 seconds.
                let cooldown = max(reply.retryAfter ?? 0, throttled && (method != "GET" || retries == 4) ? 60 : backoff)
                schedule.deferRequests(for: cooldown, at: ProcessInfo.processInfo.systemUptime)
            }
            // Retry reads only: replaying a send or draft creation can duplicate mail.
            if method == "GET", throttled || (500...599).contains(reply.status), retries < 4 {
                retries += 1
                continue
            }
            if throttled && method == "GET" { throw GmailError.throttled }
            // Safe label/trash mutations are queued; a quota rejection is temporary.
            // Keep send/draft errors as explicit HTTP rejections for outcome recovery.
            let mailboxMutation = path.hasPrefix("messages/") && ["modify", "trash", "untrash"].contains(path.split(separator: "/").last.map(String.init) ?? "")
            if throttled && mailboxMutation { throw GmailError.throttled }
            if reply.status == 403 && (method == "GET" || mailboxMutation) { throw GmailError.accessDenied(reason) }
            guard (200..<300).contains(reply.status) else { throw GmailError.http(reply.status) }
            return reply.data
        }
    }
    static func errorReason(_ data: Data) -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let reasons = error?["errors"] as? [[String: Any]]
        let details = error?["details"] as? [[String: Any]] ?? []
        let candidates = (reasons ?? []).compactMap { $0["reason"] as? String } + details.compactMap { $0["reason"] as? String }
        // Do not expose arbitrary server content or credentials in errors.
        let known = ["rateLimitExceeded", "userRateLimitExceeded", "RATE_LIMIT_EXCEEDED", "dailyLimitExceeded", "domainPolicy", "insufficientPermissions", "ACCESS_TOKEN_SCOPE_INSUFFICIENT", "accessNotConfigured", "SERVICE_DISABLED", "forbidden"]
        return candidates.first { known.contains($0) } ?? "forbidden"
    }
    static func quotaCost(_ path: String, method: String) -> Double {
        if path == "profile" || path == "labels" { return 1 }
        if path == "history" { return 2 }
        if path == "drafts" && method == "POST" { return 10 }
        if path == "messages" || path == "drafts" { return 5 }
        if path == "messages/send" || path == "drafts/send" { return 100 }
        if path.hasPrefix("threads/") { return 40 }
        if path.hasSuffix("/modify") || path.hasSuffix("/untrash") { return 5 }
        if path.hasPrefix("drafts/") && method == "PUT" { return 15 }
        if path.hasPrefix("drafts/") && method == "DELETE" { return 10 }
        return 20 // Message, attachment, draft retrieval and trash.
    }
    private func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String, query: [String: String] = [:]) async throws -> T {
        try JSONDecoder().decode(type, from: await request(path, query: query))
    }
    private func component(_ id: String) throws -> String {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { throw GmailError.invalidResponse }
        return id
    }
    func profile() async throws -> GmailProfile { try await get(GmailProfile.self, "profile") }
    func labels() async throws -> [GmailLabel] { try await get(GmailLabelPage.self, "labels").labels ?? [] }
    func messages(page: String? = nil, label: String? = nil, query: String? = nil) async throws -> GmailMessagePage {
        var values = ["maxResults": "100"]
        values["pageToken"] = page; values["labelIds"] = label; values["q"] = query
        if label == "TRASH" || label == "SPAM" { values["includeSpamTrash"] = "true" }
        return try await get(GmailMessagePage.self, "messages", query: values)
    }
    func message(_ id: String) async throws -> GmailMessageDTO {
        try await get(GmailMessageDTO.self, "messages/" + component(id), query: ["format": "full"])
    }
    func originalMessage(_ id: String) async throws -> Data {
        struct RawReply: Decodable { let raw: String }
        let data = try await request("messages/" + id, query: ["format": "raw"])
        let reply = try JSONDecoder().decode(RawReply.self, from: data)
        guard let decoded = Base64URL.decode(reply.raw) else { throw GmailError.invalidResponse }
        guard decoded.count <= DraftAttachmentStore.maximumBytes else { throw ComposeAttachmentError.tooLarge }
        return decoded
    }
    func thread(_ id: String) async throws -> GmailThreadDTO {
        try await get(GmailThreadDTO.self, "threads/" + component(id), query: ["format": "full"])
    }
    func attachment(messageID: String, attachmentID: String) async throws -> Data {
        let body = try await get(GmailBody.self, "messages/" + component(messageID) + "/attachments/" + component(attachmentID))
        guard (body.size ?? 0) <= AttachmentCache.maximumBytes,
              (body.data?.utf8.count ?? 0) <= ((AttachmentCache.maximumBytes + 2) / 3) * 4 else { throw AttachmentError.tooLarge }
        guard let data = body.data.flatMap(Base64URL.decode) else { throw GmailError.invalidResponse }
        guard data.count <= AttachmentCache.maximumBytes else { throw AttachmentError.tooLarge }
        return data
    }
    func history(since: String, page: String? = nil) async throws -> GmailHistoryPage {
        var query = ["startHistoryId": since, "maxResults": "500"]; query["pageToken"] = page
        return try await get(GmailHistoryPage.self, "history", query: query)
    }
    func modify(_ id: String, add: [String] = [], remove: [String] = []) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["addLabelIds": add, "removeLabelIds": remove])
        _ = try await request("messages/" + component(id) + "/modify", method: "POST", body: body)
    }
    func trash(_ id: String, restore: Bool = false) async throws {
        _ = try await request("messages/" + component(id) + (restore ? "/untrash" : "/trash"), method: "POST")
    }
    func send(raw: String, threadID: String?) async throws -> GmailReference {
        var object = ["raw": raw]; object["threadId"] = threadID
        let data = try await request("messages/send", method: "POST", body: JSONSerialization.data(withJSONObject: object))
        return try JSONDecoder().decode(GmailReference.self, from: data)
    }
    func drafts(query: String? = nil, page: String? = nil) async throws -> GmailDraftPage {
        var values = ["maxResults": "100"]; values["q"] = query; values["pageToken"] = page
        return try await get(GmailDraftPage.self, "drafts", query: values)
    }
    func draft(_ id: String) async throws -> GmailDraftDTO {
        try await get(GmailDraftDTO.self, "drafts/" + component(id), query: ["format": "full"])
    }
    func saveDraft(id: String?, raw: String, threadID: String?) async throws -> GmailDraftDTO {
        var message = ["raw": raw]; message["threadId"] = threadID
        let path = try id.map { "drafts/" + (try component($0)) } ?? "drafts"
        let data = try await request(path, method: id == nil ? "POST" : "PUT",
            body: JSONSerialization.data(withJSONObject: ["message": message]))
        return try JSONDecoder().decode(GmailDraftDTO.self, from: data)
    }
    func deleteDraft(_ id: String) async throws { _ = try await request("drafts/" + component(id), method: "DELETE") }
    func sendDraft(_ id: String) async throws -> GmailReference {
        let data = try await request("drafts/send", method: "POST", body: JSONSerialization.data(withJSONObject: ["id": id]))
        return try JSONDecoder().decode(GmailReference.self, from: data)
    }
}

/// Smooth pacing leaves headroom below the current 6,000-unit/minute quota.
struct GmailRequestSchedule: Sendable {
    private var nextRequestAt: TimeInterval = 0
    private var retryAt: TimeInterval = 0
    func delay(at now: TimeInterval) -> TimeInterval { max(0, max(nextRequestAt, retryAt) - now) }
    func isCoolingDown(at now: TimeInterval) -> Bool { retryAt > now }
    mutating func record(cost: Double, at now: TimeInterval) { nextRequestAt = now + cost / 60 }
    mutating func deferRequests(for delay: TimeInterval, at now: TimeInterval) { retryAt = max(retryAt, now + delay) }
}
