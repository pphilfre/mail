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
    let showFilters: Bool
    let allowStarred: Bool
    let canSelect: Bool
    let selecting: Bool
    let search: () -> Void
    let select: () -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 8) {
            Button(action: search) {
                Image(systemName: "magnifyingglass").frame(width: 44, height: 44).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityLabel("Search your mail").accessibilityIdentifier("searchButton")
            if showFilters {
                HStack(spacing: 0) {
                    ForEach(InboxQuickFilter.allCases.filter { allowStarred || $0 != .starred }) { value in
                        Button {
                            guard filter != value else { return }
                            feedback.select()
                            withAnimation(MailStyle.motion(reduced: reduceMotion)) { filter = value }
                        } label: {
                            Image(systemName: value.symbol).font(.system(size: 17, weight: filter == value ? .semibold : .regular))
                                .foregroundStyle(filter == value ? Color.primary : .secondary)
                                .frame(width: 44, height: 44)
                                .background {
                                    if filter == value {
                                        Capsule().fill(MailStyle.paper)
                                            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                                            .matchedGeometryEffect(id: "filter", in: selection)
                                    }
                                }
                                .contentShape(.rect)
                        }.buttonStyle(.plain)
                        .accessibilityLabel(value.rawValue)
                        .accessibilityAddTraits(filter == value ? [.isSelected] : [])
                        .accessibilityIdentifier("inboxFilter-\(value.id)")
                    }
                }.background(MailStyle.canvas, in: .capsule)
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
