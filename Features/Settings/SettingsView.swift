import SwiftUI

struct SettingsView: View {
    @AppStorage("showSampleInbox") private var showSamples = false

    var body: some View {
        Form {
            Section {
                Toggle("Show sample inbox", isOn: $showSamples)
                    .accessibilityIdentifier("sampleInboxToggle")
            } footer: {
                Text("Explore the inbox and reader using example messages. No account is needed.")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                LabeledContent("Requires", value: "iOS 26 or later")
                Text("Project foundation. Account connections, mail sync and sending are not yet available.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
