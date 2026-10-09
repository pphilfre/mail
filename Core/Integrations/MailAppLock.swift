import SwiftUI
import LocalAuthentication
import Observation

@MainActor
@Observable
final class MailAppLock {
    private(set) var unlocked = !UserDefaults.standard.bool(forKey: "mailAppLock")
    private(set) var authenticating = false
    var error: String?
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private var shield: UIWindow?
    @ObservationIgnored private var generation = 0

    func authenticate() async -> Bool {
        guard !authenticating else { return false }
        authenticating = true; error = nil
        let token = generation
        let context = LAContext(); self.context = context
        defer { authenticating = false; self.context = nil }
        do {
            // Face ID first, with the device passcode for biometric lockout/recovery.
            let approved = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: "Unlock your mail in Dispatch")
            guard token == generation, approved else { return false }
            unlocked = true; return true
        } catch {
            if token == generation { self.error = error.localizedDescription }
            return false
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard await authenticate() else { return }
        UserDefaults.standard.set(enabled, forKey: "mailAppLock")
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
            if UserDefaults.standard.bool(forKey: "mailAppLock") { unlocked = false }
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
