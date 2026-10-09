import SwiftUI
import SwiftData

@main
struct DispatchApp: App {
    @State private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup {
            if let container = runtime.container, let session = runtime.session {
                AppShell()
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
    }
}
