import SwiftUI

enum InboxQuickFilter: String, CaseIterable, Identifiable {
    case all = "All", unread = "Unread", starred = "Starred"
    var id: String { rawValue }
    var symbol: String { self == .all ? "tray" : self == .unread ? "envelope.badge" : "star" }
}

struct InboxHeader: View {
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var filter: InboxQuickFilter
    @Binding var mailbox: String
    let scopeTitle: String
    let accountTitle: String
    let showFilters: Bool
    let allowStarred: Bool
    let canSelect: Bool
    let selecting: Bool
    let search: () -> Void
    let select: () -> Void
    var updating = false
    var waitingUntil: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(accountTitle)
                .font(.footnote).foregroundStyle(MailStyle.secondaryInk)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Group {
                if typeSize.isAccessibilitySize { mailboxPicker.pickerStyle(.menu).frame(minHeight: 44) }
                else { mailboxPicker.pickerStyle(.segmented) }
            }.accessibilityIdentifier("mailboxSelector")
        HStack(spacing: 12) {
            Button(action: search) {
                Image(systemName: "magnifyingglass").font(MailStyle.icon)
                    .foregroundStyle(MailStyle.secondaryInk).frame(width: 44, height: 44).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityLabel("Search your mail").accessibilityIdentifier("searchButton")
            if showFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(InboxQuickFilter.allCases.filter { allowStarred || $0 != .starred }) { value in
                            Button {
                                feedback.select()
                                withAnimation(MailStyle.motion(reduced: reduceMotion)) { filter = value }
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
        }
        .padding(.horizontal, MailStyle.contentPadding).padding(.top, 8)
        .background(MailStyle.paper)
        .overlay(alignment: .bottom) { MailRule() }
    }
    private var mailboxPicker: some View {
        Picker("Mailbox", selection: $mailbox) {
            Text("Inbox").tag("Inbox")
            Text("Catch Up").tag("Catch Up")
            Text("Sent").tag("Sent")
            if !["Inbox", "Catch Up", "Sent"].contains(mailbox) { Text(scopeTitle).tag(mailbox) }
        }
    }
}
