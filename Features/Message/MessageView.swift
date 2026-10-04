import SwiftUI

struct MessageView: View {
    @Environment(AppSession.self) private var session
    let message: SampleMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(message.subject).font(.largeTitle.weight(.bold)).tracking(-0.8).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        SenderAvatar(email: message.address, name: message.sender, allowsRemoteIcon: false)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(message.sender).font(.headline)
                            Text(message.address).font(.caption).foregroundStyle(.secondary)
                            Text(message.date, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    MailBodyView(html: nil, text: message.body, remoteImages: false)
                }.padding(20).background(MailStyle.paper, in: .rect(cornerRadius: 22))
                Label("Sample message", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(MailStyle.contentPadding)
            .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(MailStyle.canvas)
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.markSampleRead(message.id) }
    }
}
