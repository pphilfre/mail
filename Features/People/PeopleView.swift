import SwiftUI
import SwiftData

struct SenderProfileRequest: Identifiable {
    var id: String { email }
    let email: String
    let name: String
    let accountID: UUID?
}

struct PeopleView: View {
    let accountID: UUID?
    @Query private var messages: [MailMessage]
    @Query private var metadata: [StoreMetadata]
    @State private var query = ""
    var body: some View {
        let notes = Dictionary(uniqueKeysWithValues: metadata.filter { $0.key.hasPrefix(SenderProfile.prefix) }.compactMap { row -> (String, SenderProfile)? in
            guard let profile = try? SenderProfile.decode(row) else { return nil }
            return (profile.email, profile)
        })
        let people = SenderInsights.directory(messages, accountID: accountID).filter { person in
            query.isEmpty || [person.email, person.name, notes[person.email]?.nickname ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
        }
        List {
            Section {
                Text("Sender profiles from mail saved on this device.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(people) { person in
                let nickname = notes[person.email]?.nickname ?? ""
                NavigationLink {
                    SenderProfileView(email: person.email, name: person.name, initialAccountID: accountID)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        SenderAvatar(email: person.email, name: nickname.isEmpty ? person.name : nickname)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nickname.isEmpty ? person.name : nickname).font(.headline)
                            Text(person.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(person.receivedCount) messages" + (person.unreadCount > 0 ? " · \(person.unreadCount) unread" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        MailRowDate(date: person.lastReceivedAt)
                    }.padding(.vertical, 6)
                }.accessibilityIdentifier("senderProfile-\(person.email)")
            }
            if people.isEmpty {
                ContentUnavailableView("No matching senders", systemImage: "person.2", description: Text("Profiles appear as mail downloads. Try a name or email address."))
            }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("People")
        .searchable(text: $query, prompt: "Sender name or email")
    }
}
