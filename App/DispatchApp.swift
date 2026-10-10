import SwiftUI
import SwiftData

@main
struct DispatchApp: App {
    @State private var runtime = AppRuntime()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
          Group {
            if let container = runtime.container, let session = runtime.session {
                Group {
                    if runtime.appLock.unlocked { AppShell() }
                    else { MailLockScreen() }
                }
                    .environment(session)
                    .environment(runtime)
                    .modelContainer(container)
            } else {
                ContentUnavailableView {
                    Label("Mail storage couldn’t open", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your saved data has been kept. Try again after unlocking your device or freeing storage.")
                } actions: {
                    Button("Try again") { runtime.openStorage() }
                }
            }
          }
        .onChange(of: scenePhase) { _, phase in runtime.appLock.phaseChanged(phase) }
        .onChange(of: runtime.appLock.unlocked) { _, unlocked in
            if unlocked { Task { await runtime.importPendingShares() } }
        }
        .onOpenURL { runtime.receiveShare($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in runtime.localModel.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { runtime.localModel.cancel() } }
        }
    }
}
