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
    let scopeTitle: String
    let showFilters: Bool
    let allowStarred: Bool
    let canSelect: Bool
    let selecting: Bool
    let search: () -> Void
    let select: () -> Void

    var body: some View {
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
                        Label(scopeTitle, systemImage: filter.symbol).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }.font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: .capsule)
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
    }
}
