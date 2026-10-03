import SwiftUI

struct MessageView: View {
    @Environment(AppSession.self) private var session
    let message: SampleMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(message.subject).font(.title2.bold()).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.sender).font(.headline)
                    Text(message.address).font(.subheadline).foregroundStyle(.secondary)
                    Text(message.date, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                MailBodyView(html: nil, text: message.body, remoteImages: false)
                Label("Sample message", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(MailStyle.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.markSampleRead(message.id) }
    }
}
