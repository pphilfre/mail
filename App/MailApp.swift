import SwiftUI

@main
struct MailApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(session)
        }
    }
}
