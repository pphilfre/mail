import SwiftUI

enum InboxQuickFilter: String, CaseIterable, Identifiable {
    case all = "All", unread = "Unread", starred = "Starred"
    var id: String { rawValue }
    var symbol: String { self == .all ? "tray" : self == .unread ? "envelope.badge" : "star" }
}

struct InboxHeader: View {
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var filter: InboxQuickFilter
    @Binding var mailbox: String
    let scopeTitle: String
    let showFilters: Bool
    let allowStarred: Bool
    let canSelect: Bool
    let selecting: Bool
    let search: () -> Void
    let select: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Picker("Mailbox", selection: $mailbox) {
                Text("Inbox").tag("Inbox")
                Text("Catch Up").tag("Catch Up")
                Text("Sent").tag("Sent")
                if !["Inbox", "Catch Up", "Sent"].contains(mailbox) { Text(scopeTitle).tag(mailbox) }
            }.pickerStyle(.segmented).accessibilityIdentifier("mailboxSelector")
        HStack(spacing: 8) {
            Button(action: search) {
                Image(systemName: "magnifyingglass").frame(width: 44, height: 44).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityLabel("Search your mail").accessibilityIdentifier("searchButton")
            if showFilters {
                Menu {
                    ForEach(InboxQuickFilter.allCases.filter { allowStarred || $0 != .starred }) { value in
                        Button {
                            feedback.select()
                            withAnimation(MailStyle.motion(reduced: reduceMotion)) { filter = value }
                        } label: {
                            Label(value == .all ? "All messages" : value.rawValue,
                                  systemImage: filter == value ? "checkmark" : value.symbol)
                        }.accessibilityIdentifier("inboxFilter-\(value.id)")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label(filter == .all ? "Filter" : filter.rawValue, systemImage: "line.3.horizontal.decrease").lineLimit(1)
                    }.font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(filter == .all ? .secondary : MailStyle.accent)
                    .accessibilityIdentifier("inboxFilterMenu").accessibilityValue(scopeTitle)
            }
            Spacer(minLength: 0)
            if canSelect {
                Button(action: select) {
                    Image(systemName: selecting ? "xmark" : "checkmark.circle").frame(width: 44, height: 44).contentShape(.rect)
                }.buttonStyle(.plain).accessibilityLabel(selecting ? "Done" : "Select")
                    .accessibilityIdentifier("selectMailButton")
            }
        }
        }.padding(.horizontal, 20).padding(.top, 8).background(MailStyle.paper)
    }
}
