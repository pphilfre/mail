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
                Text("Gmail mail is cached on this device. Remote images are blocked. Zoho, rich HTML and attachment transfer are later stages.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
