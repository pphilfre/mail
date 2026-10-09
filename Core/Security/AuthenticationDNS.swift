import Foundation

protocol AuthenticationTXTResolver: Sendable {
    func records(_ name: String) async throws -> [String]
}

enum AuthenticationError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { switch self { case .unavailable(let explanation): explanation } }
}

/// Trusted HTTPS resolver transport, with ECS disabled; no message bytes are transmitted.
actor AuthenticationDNS: AuthenticationTXTResolver {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: AuthenticationNoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func records(_ name: String) async throws -> [String] {
        guard DKIMVerifier.validDNSName(name, allowUnderscore: true) else { throw AuthenticationError.unavailable("Invalid DNS query name.") }
        var components = URLComponents(string: "https://dns.google/resolve")!
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "type", value: "TXT"),
            URLQueryItem(name: "edns_client_subnet", value: "0.0.0.0/0"), URLQueryItem(name: "cd", value: "false")]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 256_000 else { throw AuthenticationError.unavailable("DNS resolver did not return a usable response.") }
        struct Response: Decodable {
            struct Record: Decodable { let type: Int; let data: String }
            let Status: Int
            let TC: Bool?
            let Answer: [Record]?
        }
        let reply = try JSONDecoder().decode(Response.self, from: data)
        if reply.Status == 3 { return [] }
        guard reply.Status == 0, reply.TC != true else { throw AuthenticationError.unavailable("DNS query failed or was truncated. Authentication remains unknown.") }
        let answers = reply.Answer ?? []
        guard answers.count <= 32 else { throw AuthenticationError.unavailable("Too many DNS answers; authentication coverage is incomplete.") }
        return try answers.filter { $0.type == 16 }.map { try Self.txt($0.data) }
    }
    nonisolated static func txt(_ value: String) throws -> String {
        // DNS presentation format: concatenate quoted TXT chunks, including decimal escapes.
        let bytes = Array(value.utf8)
        var index = 0, output: [UInt8] = []
        while index < bytes.count {
            while index < bytes.count && [9, 32].contains(bytes[index]) { index += 1 }
            if index == bytes.count { break }
            guard bytes[index] == 34 else { throw AuthenticationError.unavailable("Malformed DNS TXT record.") }
            index += 1
            while index < bytes.count && bytes[index] != 34 {
                if bytes[index] == 92 {
                    index += 1
                    guard index < bytes.count else { throw AuthenticationError.unavailable("Malformed DNS escape.") }
                    if index + 2 < bytes.count, bytes[index...index + 2].allSatisfy({ (48...57).contains($0) }) {
                        let number = Int(bytes[index] - 48) * 100 + Int(bytes[index + 1] - 48) * 10 + Int(bytes[index + 2] - 48)
                        guard number <= 255 else { throw AuthenticationError.unavailable("Malformed DNS escape.") }
                        output.append(UInt8(number)); index += 3; continue
                    }
                }
                output.append(bytes[index]); index += 1
            }
            guard index < bytes.count, bytes[index] == 34 else { throw AuthenticationError.unavailable("Malformed DNS TXT record.") }
            index += 1
        }
        guard let result = String(bytes: output, encoding: .utf8) else { throw AuthenticationError.unavailable("Unsupported DNS TXT encoding.") }
        return result
    }
}

private final class AuthenticationNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
