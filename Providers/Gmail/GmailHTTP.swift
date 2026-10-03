import Foundation

struct HTTPReply: Sendable {
    var data: Data
    var status: Int
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
        return HTTPReply(data: data, status: response.statusCode)
    }
}

enum GmailError: LocalizedError, Equatable {
    case configuration, cancelled, invalidCallback, reconnect, invalidResponse, http(Int), invalidRecipients, uncertainSend, busy
    var errorDescription: String? {
        switch self {
        case .configuration: "Google configuration is missing or does not match the registered callback."
        case .cancelled: "Sign-in was cancelled."
        case .invalidCallback: "Google sign-in could not be verified. Try again."
        case .reconnect: "Reconnect Gmail in Accounts to restore access."
        case .invalidResponse: "Gmail returned an unreadable response. Try syncing again."
        case .http(let code): "Gmail request failed (HTTP \(code)). Check Gmail API access and try again."
        case .invalidRecipients: "Enter valid email addresses. Recipient and subject headers must not contain line breaks."
        case .uncertainSend: "Sending could not be confirmed. Check Sent in Gmail before creating another copy. Dispatch will not resend this message automatically."
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
