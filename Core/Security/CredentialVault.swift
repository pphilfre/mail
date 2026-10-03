import Foundation
import Security

struct OAuthCredentials: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var grantedScopes: [String]

    var description: String { "OAuthCredentials(redacted)" }
    var debugDescription: String { description }
}

struct CredentialVaultError: LocalizedError, Sendable {
    let status: OSStatus
    var errorDescription: String? {
        "Secure credential storage failed (\(status)). Reconnect the account after checking app signing."
    }
}

actor CredentialVault {
    private let service: String
    init(service: String = "dev.freddiephilpot.dispatch.oauth") { self.service = service }

    func save(_ credentials: OAuthCredentials, for accountID: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = baseQuery(accountID)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            values.forEach { item[$0.key] = $0.value }
            let add = SecItemAdd(item as CFDictionary, nil)
            guard add == errSecSuccess else { throw CredentialVaultError(status: add) }
        } else if update != errSecSuccess {
            throw CredentialVaultError(status: update)
        }
    }

    func load(for accountID: UUID) throws -> OAuthCredentials? {
        var query = baseQuery(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialVaultError(status: status) }
        guard let data = result as? Data else { throw CredentialVaultError(status: errSecDecode) }
        return try JSONDecoder().decode(OAuthCredentials.self, from: data)
    }

    func remove(for accountID: UUID) throws {
        let status = SecItemDelete(baseQuery(accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialVaultError(status: status) }
    }

    private func baseQuery(_ accountID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: accountID.uuidString,
         kSecAttrSynchronizable as String: false]
    }
}
