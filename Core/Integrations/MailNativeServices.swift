import BackgroundTasks
import UserNotifications
import UIKit
import Observation

@MainActor @Observable final class MailNativeServices {
    static let refreshIdentifier = "dev.freddiephilpot.dispatch.refresh"
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    var error: String?
    var configuringStorage = false
    var refreshAvailable: Bool { UIApplication.shared.backgroundRefreshStatus == .available }
    var notificationsEnabled: Bool { [.authorized, .provisional, .ephemeral].contains(notificationStatus) }

    func updateAuthorization() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func enableNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await updateAuthorization()
        } catch { self.error = error.localizedDescription }
    }
    func scheduleRefresh() {
        guard UserDefaults.standard.bool(forKey: "backgroundMailRefresh"), refreshAvailable else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do { try BGTaskScheduler.shared.submit(request); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func cancelRefresh() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshIdentifier) }
    func notifyNewMail(count: Int) async {
        await updateAuthorization()
        guard count > 0, notificationsEnabled, UserDefaults.standard.bool(forKey: "notifyNewMail") else { return }
        let content = UNMutableNotificationContent()
        content.title = "Dispatch"
        content.body = count == 1 ? "You have a new message." : "You have \(count) new messages."
        content.sound = .default
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "dispatch-new-mail", content: content, trigger: nil))
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor extension AppRuntime {
    func configureBackgroundRefresh(_ enabled: Bool) async throws {
        guard !nativeServices.configuringStorage else { throw BackgroundMailStorageError.busy }
        nativeServices.configuringStorage = true; nativeServices.error = nil
        defer { nativeServices.configuringStorage = false }
        let root = URL.applicationSupportDirectory.appending(path: "Dispatch", directoryHint: .isDirectory)
        let protection = LocalMailProtection.storageProtection(backgroundRefresh: enabled)
        let previous = LocalMailProtection.storageProtection(backgroundRefresh: UserDefaults.standard.bool(forKey: "backgroundMailRefresh"))
        do {
            try await Task.detached(priority: .utility) {
                try LocalMailProtection.protectTree(root, protection: protection, preservingDraftAttachments: true)
            }.value
        } catch {
            do {
                try await Task.detached(priority: .utility) {
                    try LocalMailProtection.protectTree(root, protection: previous, preservingDraftAttachments: true)
                }.value
            } catch { throw BackgroundMailStorageError.rollbackFailed }
            throw error
        }
        UserDefaults.standard.set(enabled, forKey: "backgroundMailRefresh")
        if enabled { nativeServices.scheduleRefresh() } else { nativeServices.cancelRefresh() }
    }
    func refreshInBackground() async {
        defer { nativeServices.scheduleRefresh() }
        guard UserDefaults.standard.bool(forKey: "backgroundMailRefresh"), !storageFailed,
              appLock.unlocked, let repository, let gmail else { return }
        do {
            // Initial account download does not announce historical messages as new mail.
            let syncedAccounts = Set(try repository.accounts().filter { $0.lastSyncAt != nil }.map(\.id))
            let before = Set(try repository.recentMessages(limit: 500).map(\.identity))
            await gmail.syncAll()
            try Task.checkCancellation()
            let arrivals = try repository.recentMessages(limit: 500).filter {
                syncedAccounts.contains($0.accountID) && !before.contains($0.identity) && $0.isInbox && !$0.isRead && !$0.isSpam && !$0.isTrash
            }
            await nativeServices.notifyNewMail(count: arrivals.count)
            // Queued sends retain existing uncertain-send safeguards and respect app lock.
            await deliverScheduledMail()
        } catch { if !Task.isCancelled { nativeServices.error = error.localizedDescription } }
    }
}

enum BackgroundMailStorageError: LocalizedError {
    case busy, rollbackFailed
    var errorDescription: String? {
        switch self {
        case .busy: "Storage protection is already being updated."
        case .rollbackFailed: "Storage protection could not be fully updated or restored. Background refresh preferences were kept. Review Device Storage in Security Inspector and retry while your device is unlocked."
        }
    }
}
