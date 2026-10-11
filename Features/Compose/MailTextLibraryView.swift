import SwiftUI

struct MailTextLibraryView: View {
    let kind: String
    let accountID: UUID?
    @AppStorage private var raw: String
    @State private var editing: MailTextItem?
    private var items: [MailTextItem] {
        if !raw.isEmpty, let data = raw.data(using: .utf8), let items = try? JSONDecoder().decode([MailTextItem].self, from: data) { return items }
        return MailTextLibrary.read(kind, accountID: accountID)
    }
    init(kind: String, accountID: UUID? = nil) {
        self.kind = kind; self.accountID = accountID
        _raw = AppStorage(wrappedValue: "", MailTextLibrary.key(kind, accountID: accountID))
    }
    var body: some View {
        List {
            if items.isEmpty { ContentUnavailableView("No \(kind.lowercased())", systemImage: "text.badge.plus", description: Text("Add reusable text with the plus button.")) }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button { editing = item } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).foregroundStyle(.primary)
                        Text(kind == "Signatures" && index == 0 ? "Default signature" : item.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.contextMenu {
                    if kind == "Signatures" && index != 0 {
                        Button("Use by default") { raw = MailTextLibrary.encode([item] + items.filter { $0.id != item.id }) }
                    }
                }
            }.onDelete { offsets in var updated = items; updated.remove(atOffsets: offsets); raw = MailTextLibrary.encode(updated) }
        }.navigationTitle(kind)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Add", systemImage: "plus") { editing = MailTextItem(name: "", body: "") } } }
            .sheet(item: $editing) { item in
                NavigationStack { MailTextEditor(item: item, isTemplate: kind == "Templates") { updated in
                    var all = items
                    if let index = all.firstIndex(where: { $0.id == updated.id }) { all[index] = updated } else { all.append(updated) }
                    raw = MailTextLibrary.encode(all)
                } }
            }
    }
}

private struct MailTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: MailTextItem
    let isTemplate: Bool
    let save: (MailTextItem) -> Void
    var body: some View {
        Form {
            TextField("Name", text: $item.name)
            if isTemplate { TextField("Subject", text: $item.subject) }
            TextEditor(text: $item.body).frame(minHeight: 200).accessibilityLabel("Reusable text")
        }.navigationTitle("Edit text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(item); dismiss() }
                        .disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
    }
}
