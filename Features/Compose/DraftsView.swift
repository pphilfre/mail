import SwiftUI

struct DraftsView: View {
    @Environment(AppSession.self) private var session
    @State private var editingDraft: LocalDraft?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(session.drafts) { draft in
                Button {
                    editingDraft = draft
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.displaySubject).font(.headline).foregroundStyle(.primary)
                        Text(draft.to.isEmpty ? "No recipients" : draft.to)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Text(draft.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .onDelete { offsets in
                do { try session.deleteDraft(at: offsets) }
                catch { errorMessage = error.localizedDescription }
            }
        }
        .overlay {
            if session.drafts.isEmpty {
                ContentUnavailableView("No drafts", systemImage: "doc", description: Text("Saved drafts will appear here."))
            }
        }
        .navigationTitle("On-device drafts")
        .sheet(item: $editingDraft) { draft in
            NavigationStack { ComposeView(draft: draft) }
        }
        .alert("Couldn’t delete draft", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
