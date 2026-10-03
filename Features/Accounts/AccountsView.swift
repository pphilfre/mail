import SwiftUI

struct AccountsView: View {
    var body: some View {
        List {
            Section {
                ContentUnavailableView("No accounts connected", systemImage: "person.crop.circle.badge.plus",
                    description: Text("Google and Zoho account connections are coming in the next implementation stages."))
                    .listRowBackground(Color.clear)
            }
            Section("Planned providers") {
                Label("Gmail", systemImage: "envelope")
                Label("Zoho Mail", systemImage: "envelope")
            }
        }
        .navigationTitle("Accounts")
    }
}
