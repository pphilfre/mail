import SwiftUI

@main
struct DispatchApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(session)
        }
    }
}
