import SwiftUI

@main
struct Dispatch: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(session)
        }
    }
}
