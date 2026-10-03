import SwiftUI

struct AppShell: View {
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
        .sheet(isPresented: $showingCompose) {
            NavigationStack { ComposeView() }
        }
    }
}
