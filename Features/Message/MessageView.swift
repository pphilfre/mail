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
                Text(message.body)
                    .font(.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label("Sample message", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(MailStyle.contentPadding)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.markSampleRead(message.id) }
    }
}
