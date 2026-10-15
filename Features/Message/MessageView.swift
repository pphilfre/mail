import SwiftUI

struct MessageView: View {
    @Environment(AppSession.self) private var session
    let message: SampleMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(message.subject).font(MailStyle.readerTitle).foregroundStyle(MailStyle.ink).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        SenderAvatar(email: message.address, name: message.sender, allowsRemoteIcon: false)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(message.sender).font(.headline)
                            Text(message.address).font(.footnote).foregroundStyle(MailStyle.secondaryInk)
                            Text(message.date, format: .dateTime.day().month().year().hour().minute())
                                .font(.footnote).foregroundStyle(MailStyle.secondaryInk)
                        }
                    }
                    MailRule().padding(.vertical, 8)
                    MailBodyView(html: nil, text: message.body, remoteImages: false)
                }.padding(.vertical, 8)
                Label("Sample message", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(MailStyle.secondaryInk)
            }
            .padding(MailStyle.contentPadding)
            .frame(maxWidth: MailStyle.readingWidth, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(MailStyle.paper)
        .foregroundStyle(MailStyle.ink)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: message.subject + "\n\n" + message.body) {
                    Image(systemName: "square.and.arrow.up").font(MailStyle.icon).frame(width: 44, height: 44)
                }.labelStyle(.iconOnly).buttonStyle(.plain)
                    .accessibilityLabel("Share sample message")
            }
        }
        .onAppear { session.markSampleRead(message.id) }
    }
}
