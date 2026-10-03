import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct GoogleConfiguration: Codable, Sendable {
    let clientID: String
    let callbackScheme: String
    static let scope = "https://www.googleapis.com/auth/gmail.modify"
    var redirectURI: String { callbackScheme + ":/oauth2redirect" }
    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "GoogleOAuth", withExtension: "plist") else { throw GmailError.configuration }
        let config = try PropertyListDecoder().decode(Self.self, from: Data(contentsOf: url))
        let reversed = config.clientID.split(separator: ".").reversed().joined(separator: ".")
        guard reversed == config.callbackScheme else { throw GmailError.configuration }
        return config
    }
}

struct GoogleAuthorization: Sendable {
    let configuration: GoogleConfiguration
    let verifier: String
    let state: String
    init(configuration: GoogleConfiguration, verifier: String? = nil, state: String? = nil) throws {
        self.configuration = configuration
        self.verifier = try verifier ?? Self.random()
        self.state = try state ?? Self.random()
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw GmailError.invalidCallback }
        return Base64URL.encode(Data(bytes))
    }
    var challenge: String { Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    var url: URL {
        var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        parts.queryItems = ["client_id": configuration.clientID, "redirect_uri": configuration.redirectURI,
            "response_type": "code", "scope": GoogleConfiguration.scope, "state": state,
            "code_challenge": challenge, "code_challenge_method": "S256", "access_type": "offline",
            "prompt": "consent select_account"].map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }
    func code(from url: URL) throws -> String {
        guard url.scheme == configuration.callbackScheme, url.host == nil, url.path == "/oauth2redirect",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw GmailError.invalidCallback }
        let items = parts.queryItems ?? []
        func single(_ name: String) -> String? {
            let values = items.filter { $0.name == name }
            return values.count == 1 ? values[0].value : nil
        }
        guard single("state") == state else { throw GmailError.invalidCallback }
        if single("error") != nil { throw GmailError.cancelled }
        guard let code = single("code"), !code.isEmpty else { throw GmailError.invalidCallback }
        return code
    }
}

struct GoogleTokenReply: Decodable, Sendable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
    let scope: String?
    func credentials(previous: OAuthCredentials? = nil) throws -> OAuthCredentials {
        let scopes = scope?.split(separator: " ").map(String.init) ?? previous?.grantedScopes ?? []
        guard !access_token.isEmpty, expires_in > 0, let refresh = refresh_token ?? previous?.refreshToken,
              !refresh.isEmpty, scopes.contains(GoogleConfiguration.scope) else { throw GmailError.reconnect }
        return OAuthCredentials(accessToken: access_token, refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(Double(expires_in)), grantedScopes: scopes)
    }
}

enum GoogleTokenEndpoint {
    static func exchange(_ values: [String: String], transport: any MailHTTPTransport) async throws -> GoogleTokenReply {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.httpBody = formData(values)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let reply = try await transport.execute(request)
        guard (200..<300).contains(reply.status) else { throw GmailError.reconnect }
        return try JSONDecoder().decode(GoogleTokenReply.self, from: reply.data)
    }
}

/// The system browser owns the login UI. Passwords and cookies never enter Dispatch.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var active: ASWebAuthenticationSession?
    private var anchor: UIWindow?
    func connect(configuration: GoogleConfiguration, transport: any MailHTTPTransport) async throws -> OAuthCredentials {
        guard active == nil else { throw GmailError.busy }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow)
        else { throw GmailError.cancelled }
        anchor = window
        defer { active = nil; anchor = nil }
        let authorization = try GoogleAuthorization(configuration: configuration)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authorization.url, callbackURLScheme: configuration.callbackScheme) { url, _ in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: GmailError.cancelled) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            active = session
            if !session.start() { active = nil; continuation.resume(throwing: GmailError.cancelled) }
        }
        let code = try authorization.code(from: callback)
        let reply = try await GoogleTokenEndpoint.exchange([
            "client_id": configuration.clientID, "code": code, "code_verifier": authorization.verifier,
            "redirect_uri": configuration.redirectURI, "grant_type": "authorization_code"
        ], transport: transport)
        return try reply.credentials()
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor! }
}

actor GoogleTokenManager {
    let configuration: GoogleConfiguration
    let vault: CredentialVault
    let transport: any MailHTTPTransport
    private var refreshing: [UUID: Task<String, Error>] = [:]
    init(configuration: GoogleConfiguration, vault: CredentialVault, transport: any MailHTTPTransport) {
        self.configuration = configuration; self.vault = vault; self.transport = transport
    }
    func token(for id: UUID, force: Bool = false) async throws -> String {
        if let task = refreshing[id] { return try await task.value }
        guard let stored = try await vault.load(for: id) else { throw GmailError.reconnect }
        if !force && stored.expiresAt.timeIntervalSinceNow > 60 { return stored.accessToken }
        let task = Task { [configuration, vault, transport] in
            let reply = try await GoogleTokenEndpoint.exchange(["client_id": configuration.clientID,
                "refresh_token": stored.refreshToken, "grant_type": "refresh_token"], transport: transport)
            let refreshed = try reply.credentials(previous: stored)
            // A removed or reconnected account must not be restored by a late refresh.
            guard let current = try await vault.load(for: id), current == stored else { throw GmailError.reconnect }
            try await vault.save(refreshed, for: id)
            return refreshed.accessToken
        }
        refreshing[id] = task
        defer { refreshing[id] = nil }
        return try await task.value
    }
}
