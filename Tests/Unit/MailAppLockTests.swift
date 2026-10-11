import XCTest
@testable import DispatchMail

@MainActor
final class MailAppLockTests: XCTestCase {
    func testEnablingAndDisablingRequireSuccessfulAuthentication() async {
        let domain = "MailAppLockTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let rejected = MailAppLock(defaults: defaults, evaluator: { false })
        await rejected.setEnabled(true)
        XCTAssertFalse(defaults.bool(forKey: "mailAppLock"))
        let approved = MailAppLock(defaults: defaults, evaluator: { true })
        await approved.setEnabled(true)
        XCTAssertTrue(defaults.bool(forKey: "mailAppLock"))
        let locked = MailAppLock(defaults: defaults, evaluator: { false })
        XCTAssertFalse(locked.unlocked)
        await locked.setEnabled(false)
        XCTAssertTrue(defaults.bool(forKey: "mailAppLock"))
        XCTAssertFalse(locked.unlocked)
    }

    func testBackgroundInvalidatesPendingAuthenticationAndActiveDoesNotUnlock() async {
        let domain = "MailAppLockTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defaults.set(true, forKey: "mailAppLock")
        defer { defaults.removePersistentDomain(forName: domain) }
        let lock = MailAppLock(defaults: defaults, evaluator: {
            try await Task.sleep(for: .milliseconds(100)); return true
        })
        let attempt = Task { await lock.authenticate() }
        while !lock.authenticating { await Task.yield() }
        lock.phaseChanged(.background)
        lock.phaseChanged(.active)
        let result = await attempt.value
        XCTAssertFalse(result)
        XCTAssertFalse(lock.unlocked)
        XCTAssertFalse(lock.authenticating)
    }
}
