import SwiftUI

enum InboxQuickFilter: String, CaseIterable, Identifiable {
    case all = "All", unread = "Unread", starred = "Starred"
    var id: String { rawValue }
    var symbol: String { self == .all ? "tray" : self == .unread ? "envelope.badge" : "star" }
}

struct InboxHeader: View {
    @Environment(MailFeedback.self) private var feedback
    @Binding var filter: InboxQuickFilter
    let showFilters: Bool
    let allowStarred: Bool
    let canSelect: Bool
    let selecting: Bool
    let select: () -> Void
    var updating = false
    var waitingUntil: Date?

    var body: some View {
        HStack(spacing: 12) {
            if showFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(InboxQuickFilter.allCases.filter { allowStarred || $0 != .starred }) { value in
                            Button {
                                feedback.select()
                                filter = value
                            } label: {
                                MailFilterLabel(title: value.rawValue, selected: filter == value)
                            }.buttonStyle(.plain).accessibilityIdentifier("inboxFilter-\(value.id)")
                                .accessibilityAddTraits(filter == value ? [.isSelected] : [])
                        }
                    }
                }.accessibilityIdentifier("inboxFilterBar")
            }
            Spacer(minLength: 0)
            if updating { ProgressView().controlSize(.small).accessibilityLabel("Updating mail").accessibilityIdentifier("mailSyncSpinner") }
            else if let waitingUntil { GmailWaitStatus(deadline: waitingUntil).font(.caption) }
            if canSelect {
                Button(action: select) {
                    Image(systemName: selecting ? "xmark" : "checkmark.circle").font(MailStyle.icon)
                        .foregroundStyle(selecting ? MailStyle.accent : MailStyle.secondaryInk)
                        .frame(width: 44, height: 44).contentShape(.rect)
                }.buttonStyle(.plain).accessibilityLabel(selecting ? "Done" : "Select")
                    .accessibilityIdentifier("selectMailButton")
            }
        }
        .padding(.horizontal, MailStyle.contentPadding).padding(.top, 8)
        .background(MailStyle.paper)
        .overlay(alignment: .bottom) { MailRule() }
    }
}
