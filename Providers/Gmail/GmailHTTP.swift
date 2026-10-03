import Foundation

struct HTTPReply: Sendable {
    var data: Data
    var status: Int
    var retryAfter: TimeInterval? = nil
}

protocol MailHTTPTransport: Sendable {
    func execute(_ request: URLRequest) async throws -> HTTPReply
}

struct URLSessionMailTransport: MailHTTPTransport {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }
    func execute(_ request: URLRequest) async throws -> HTTPReply {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GmailError.invalidResponse }
        return HTTPReply(data: data, status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
    }
}

enum GmailError: LocalizedError, Equatable {
    case throttled, accessDenied(String)
    case configuration, cancelled, invalidCallback, reconnect, invalidResponse, http(Int), invalidRecipients, uncertainSend, uncertainDraft, busy
    var errorDescription: String? {
        switch self {
        case .throttled: "Gmail temporarily limited syncing. Your downloaded mail is safe. Wait a moment, then pull to refresh."
        case .accessDenied(let reason): "Gmail denied access (\(reason)). Reconnect Gmail in Accounts. If this continues, check the Google project's Gmail API and your Workspace administrator's restrictions."
        case .configuration: "Google configuration is missing or does not match the registered callback."
        case .cancelled: "Sign-in was cancelled."
        case .invalidCallback: "Google sign-in could not be verified. Try again."
        case .reconnect: "Reconnect Gmail in Accounts to restore access."
        case .invalidResponse: "Gmail returned an unreadable response. Try syncing again."
        case .http(let code): "Gmail request failed (HTTP \(code)). Check Gmail API access and try again."
        case .invalidRecipients: "Enter valid email addresses. Recipient and subject headers must not contain line breaks."
        case .uncertainSend: "Sending could not be confirmed. Check Sent in Gmail before creating another copy. Dispatch will not resend this message automatically."
        case .uncertainDraft: "The Gmail draft upload could not be confirmed. Your local draft is safe. Check Gmail Drafts, then try Save to Gmail again; Dispatch will look for the existing copy before creating another."
        case .busy: "This account is already connecting."
        }
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ value: String) -> Data? {
        let base = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base + String(repeating: "=", count: (4 - base.count % 4) % 4))
    }
}

func formData(_ values: [String: String]) -> Data {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return Data(values.sorted { $0.key < $1.key }.map {
        "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
    }.joined(separator: "&").utf8)
}
