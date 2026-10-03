import SwiftUI

struct InboxView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("showSampleInbox") private var showSamples = false

    var body: some View {
        List {
            if let error = session.storageError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if !session.drafts.isEmpty {
                Section {
                    NavigationLink {
                        DraftsView()
                    } label: {
                        Label {
                            HStack {
                                Text("On-device drafts")
                                Spacer()
                                Text(session.drafts.count, format: .number).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "doc") }
                    }
                }
            }
            if showSamples {
                Section {
                    ForEach(session.sampleMessages) { message in
                        NavigationLink {
                            MessageView(message: message)
                        } label: { MessageRow(message: message) }
                    }
                } header: {
                    Text("Sample inbox")
                } footer: {
                    Text("These messages are examples. Turn them off in Settings.")
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Your inbox starts here", systemImage: "tray")
                    } description: {
                        Text("No accounts are connected. Explore sample mail in Settings while account connections are being built.")
                    }
                    .accessibilityIdentifier("emptyInbox")
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Inbox")
    }
}

struct MessageRow: View {
    let message: SampleMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.isRead ? Color.clear : MailStyle.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: MailStyle.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.sender).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(message.date, format: .dateTime.hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(message.subject).font(.subheadline).lineLimit(1)
                Text(message.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityValue(message.isRead ? "Read" : "Unread")
    }
}
