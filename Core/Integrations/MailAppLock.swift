import SwiftUI
import LocalAuthentication
import Observation

@MainActor
@Observable
final class MailAppLock {
    private(set) var unlocked: Bool
    private(set) var authenticating = false
    var error: String?
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private var shield: UIWindow?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let evaluator: (@MainActor () async throws -> Bool)?

    init(defaults: UserDefaults = .standard, evaluator: (@MainActor () async throws -> Bool)? = nil) {
        self.defaults = defaults; self.evaluator = evaluator
        unlocked = !defaults.bool(forKey: "mailAppLock")
    }

    func authenticate() async -> Bool {
        guard !authenticating else { return false }
        authenticating = true; error = nil
        let token = generation
        let context = LAContext(); self.context = context
        defer { authenticating = false; self.context = nil }
        do {
            // Face ID first, with the device passcode for biometric lockout/recovery.
            let approved: Bool
            if let evaluator { approved = try await evaluator() }
            else { approved = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your mail in Dispatch") }
            guard token == generation, approved else { return false }
            unlocked = true; return true
        } catch {
            if token == generation { self.error = error.localizedDescription }
            return false
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard await authenticate() else { return }
        defaults.set(enabled, forKey: "mailAppLock")
    }

    func phaseChanged(_ phase: ScenePhase) {
        if phase != .active {
            // Separate window also covers sheets, file previews and composer during snapshots.
            if shield == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                let controller = UIViewController(); controller.view.backgroundColor = .systemBackground
                window.rootViewController = controller; window.isHidden = false; shield = window
            }
        }
        if phase == .background {
            generation += 1; context?.invalidate()
            if defaults.bool(forKey: "mailAppLock") { unlocked = false }
        }
        if phase == .active { shield?.isHidden = true; shield = nil }
    }
}

struct MailLockScreen: View {
    @Environment(AppRuntime.self) private var runtime
    var body: some View {
        ContentUnavailableView {
            Label("Mail is locked", systemImage: "lock.fill")
        } description: {
            Text(runtime.appLock.error ?? "Use Face ID or your device passcode to unlock Dispatch.")
        } actions: {
            Button("Unlock", systemImage: "faceid") { Task { _ = await runtime.appLock.authenticate() } }
                .disabled(runtime.appLock.authenticating)
        }
    }
}
