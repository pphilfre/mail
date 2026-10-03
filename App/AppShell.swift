import SwiftUI

struct AppShell: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingCompose = false

    var body: some View {
        TabView {
            Tab("Mail", systemImage: "tray") {
                NavigationStack {
                    InboxView()
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Compose", systemImage: "square.and.pencil") {
                                    showingCompose = true
                                }
                                .accessibilityIdentifier("composeButton")
                            }
                        }
                }
            }
            Tab("Accounts", systemImage: "person.crop.circle") {
                NavigationStack { AccountsView() }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .tint(MailStyle.accent)
        .task { await runtime.gmail?.syncAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await runtime.gmail?.syncAll() } }
        }
        .sheet(isPresented: $showingCompose) {
            NavigationStack { ComposeView() }
        }
    }
}
