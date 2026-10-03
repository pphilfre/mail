import XCTest
@testable import DispatchMail

@MainActor
final class CredentialVaultTests: XCTestCase {
    func testKeychainRoundTripRotationAndDeletion() async throws {
        let vault = CredentialVault(service: "dispatch.tests.\(UUID().uuidString)")
        let accountID = UUID()
        addTeardownBlock { try await vault.remove(for: accountID) }
        var credentials = OAuthCredentials(accessToken: "test-access", refreshToken: "test-refresh",
            expiresAt: Date(timeIntervalSince1970: 1234), grantedScopes: ["mail"])
        try await vault.save(credentials, for: accountID)
        let stored = try await vault.load(for: accountID)
        XCTAssertEqual(stored, credentials)
        credentials.accessToken = "rotated-access"
        credentials.refreshToken = "rotated-refresh"
        try await vault.save(credentials, for: accountID)
        let rotated = try await vault.load(for: accountID)
        XCTAssertEqual(rotated, credentials)
        try await vault.remove(for: accountID)
        let deleted = try await vault.load(for: accountID)
        XCTAssertNil(deleted)
    }

    func testCredentialsAreIsolatedByAccount() async throws {
        let vault = CredentialVault(service: "dispatch.tests.\(UUID().uuidString)")
        let first = UUID(), second = UUID()
        addTeardownBlock { try await vault.remove(for: first); try await vault.remove(for: second) }
        let credentials = OAuthCredentials(accessToken: "first", refreshToken: "refresh", expiresAt: Date(), grantedScopes: [])
        try await vault.save(credentials, for: first)
        let other = try await vault.load(for: second)
        XCTAssertNil(other)
        try await vault.remove(for: second) // Removing an absent item is idempotent.
        let existing = try await vault.load(for: first)
        XCTAssertEqual(existing, credentials)
    }

    func testCredentialDescriptionsNeverRevealTokens() {
        let credentials = OAuthCredentials(accessToken: "private-access", refreshToken: "private-refresh", expiresAt: Date(), grantedScopes: [])
        XCTAssertEqual(String(describing: credentials), "OAuthCredentials(redacted)")
        XCTAssertEqual(String(reflecting: credentials), "OAuthCredentials(redacted)")
    }
}
