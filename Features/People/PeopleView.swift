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
    @State private var filter = "All"
    var body: some View {
        let notes = Dictionary(uniqueKeysWithValues: metadata.filter { $0.key.hasPrefix(SenderProfile.prefix) }.compactMap { row -> (String, SenderProfile)? in
            guard let profile = try? SenderProfile.decode(row) else { return nil }
            return (profile.email, profile)
        })
        let people = SenderInsights.directory(messages, accountID: accountID).filter { person in
            let matches = query.isEmpty || [person.email, person.name, notes[person.email]?.nickname ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
            return matches && (filter != "Favourites" || notes[person.email]?.isFavourite == true)
                && (filter != "Recent" || person.lastReceivedAt >= (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast))
        }.sorted {
            if filter == "Frequent", $0.receivedCount != $1.receivedCount { return $0.receivedCount > $1.receivedCount }
            if filter == "All" || filter == "Favourites" { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.lastReceivedAt > $1.lastReceivedAt
        }
        List {
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
                }.listRowBackground(MailStyle.paper).accessibilityIdentifier("senderProfile-\(person.email)")
            }
            if people.isEmpty {
                ContentUnavailableView("No matching senders", systemImage: "person.2", description: Text("Profiles appear as mail downloads. Try a name or email address."))
            }
        }
        .modifier(MailWorkspaceList())
        .navigationTitle("People").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Sender name or email")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(["Recent", "Frequent", "Favourites", "All"], id: \.self) { value in
                        Button { filter = value } label: { MailFilterLabel(title: value, selected: filter == value) }
                            .accessibilityAddTraits(filter == value ? .isSelected : [])
                    }
                }.buttonStyle(.plain).padding(.horizontal, MailStyle.contentPadding)
            }.background(MailStyle.paper).overlay(alignment: .bottom) { MailRule() }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { MailNavigationTitle(title: "People") }
            ToolbarItem(placement: .topBarLeading) {
                Menu("People filters", systemImage: "line.3.horizontal.decrease") {
                    Picker("People", selection: $filter) { ForEach(["Recent", "Frequent", "Favourites", "All"], id: \.self) { Text($0).tag($0) } }
                }
            }
        }
    }
}
