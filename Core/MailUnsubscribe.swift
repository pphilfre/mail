import Foundation

struct MailUnsubscribe: Codable, Sendable {
    var web: URL?
    var mail: URL?
    var oneClick = false
    static func key(_ message: MailMessage) -> String { "mail-unsubscribe:\(message.identity)" }
    init(header: String, post: String, signature: String, authentication: String) {
        for part in header.split(separator: ",") {
            let raw = part.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            guard let url = URL(string: raw), url.user == nil, url.password == nil else { continue }
            if url.scheme?.lowercased() == "https", let host = url.host, Self.publicHost(host), web == nil { web = url }
            if url.scheme?.lowercased() == "mailto", MailMIME.valid(url.path), mail == nil { mail = url }
        }
        let signed = signature.lowercased().split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("h=") }?.dropFirst(2).split(separator: ":").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        let auth = authentication.lowercased()
        oneClick = web != nil && post.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "list-unsubscribe=one-click" &&
            auth.hasPrefix("mx.google.com;") && auth.contains("dkim=pass") && signed.contains("list-unsubscribe") && signed.contains("list-unsubscribe-post")
    }
    static func publicHost(_ host: String) -> Bool {
        let host = host.lowercased()
        guard host.contains("."), !host.contains(":"), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              host != "localhost", !host.hasSuffix(".internal") else { return false }
        // Domain names only: do not contact literal IPs carried in untrusted email headers.
        return !host.allSatisfy { $0.isNumber || $0 == "." }
    }
    func perform() async throws {
        guard oneClick, let web else { throw GmailError.invalidResponse }
        var request = URLRequest(url: web)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("List-Unsubscribe=One-Click".utf8)
        request.timeoutInterval = 30
        let session = URLSession(configuration: .ephemeral, delegate: UnsubscribeRedirectPolicy(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw GmailError.invalidResponse }
    }
}

private final class UnsubscribeRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
