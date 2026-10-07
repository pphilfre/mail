import SwiftUI

enum InboxQuickFilter: String, CaseIterable, Identifiable {
    case all = "All", unread = "Unread", starred = "Starred"
    var id: String { rawValue }
}

struct InboxHeader: View {
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let scope: String
    let count: Int
    let grouped: Bool
    @Binding var filter: InboxQuickFilter
    let showFilters: Bool
    let allowStarred: Bool
    let canSelect: Bool
    let selecting: Bool
    let search: () -> Void
    let select: () -> Void
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(scope).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 12)
                    if canSelect {
                        Button(action: select) {
                            Text(selecting ? "Done" : "Select").font(.subheadline.weight(.medium))
                                .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                        }.buttonStyle(.plain).foregroundStyle(MailStyle.accent)
                            .accessibilityIdentifier("selectMailButton")
                    }
                }
                HStack {
                    Text("\(count) \(grouped ? (count == 1 ? "conversation" : "conversations") : (count == 1 ? "message" : "messages"))")
                        .accessibilityIdentifier("inboxResultCount")
                    Spacer(minLength: 12)
                }.font(.caption).foregroundStyle(.secondary)
            }
            Button(action: search) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                    Text("Search your mail").font(.body)
                    Spacer()
                }
                .foregroundStyle(.secondary).padding(.horizontal, 16).frame(minHeight: 44)
                .background(MailStyle.canvas, in: .rect(cornerRadius: 16))
            }.buttonStyle(.plain).accessibilityIdentifier("searchButton")
            if showFilters {
                HStack(spacing: 0) {
                    ForEach(InboxQuickFilter.allCases.filter { allowStarred || $0 != .starred }) { value in
                        Button {
                            guard filter != value else { return }
                            feedback.select()
                            withAnimation(MailStyle.motion(reduced: reduceMotion)) { filter = value }
                        } label: {
                            Text(value.rawValue).font(.subheadline.weight(filter == value ? .semibold : .regular))
                                .foregroundStyle(filter == value ? Color.primary : .secondary)
                                .frame(maxWidth: .infinity).frame(minHeight: 44)
                                .background {
                                    if filter == value {
                                        Capsule().fill(MailStyle.paper)
                                            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                                            .matchedGeometryEffect(id: "filter", in: selection)
                                    }
                                }
                                .contentShape(.rect)
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(filter == value ? [.isSelected] : [])
                        .accessibilityIdentifier("inboxFilter-\(value.id)")
                    }
                }.padding(4).background(MailStyle.canvas, in: .capsule)
            }
        }
    }
}
