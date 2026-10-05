import SwiftUI
import SwiftData

struct CollectionsView: View {
    let accountID: UUID?
    @Query private var metadata: [StoreMetadata]
    @Query private var messages: [MailMessage]
    @State private var creating = false
    @State private var query = ""
    private var collections: [MailCollection] {
        metadata.filter { $0.key.hasPrefix(MailCollection.prefix) }.compactMap { try? MailCollection.decode($0) }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        List {
            Section {
                Text("Bring related conversations, files, tasks and receipts together. Collections stay on this device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(collections) { collection in
                NavigationLink { CollectionDetailView(collectionID: collection.id, accountID: accountID) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(collection.name, systemImage: "folder").font(.headline)
                        Text("\(MailConversation.rows(collection.messages(in: messages, accountID: accountID), grouped: true).count) downloaded conversations")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }.accessibilityIdentifier("collection-\(collection.name)")
            }
            if collections.isEmpty {
                ContentUnavailableView("Your next project", systemImage: "folder.badge.plus",
                    description: Text("Create a collection for a trip, purchase or work project, then add its conversations."))
            }
            if metadata.contains(where: { $0.key.hasPrefix(MailCollection.prefix) && (try? MailCollection.decode($0)) == nil }) {
                Text(MailCollectionError.invalidData.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Collections").searchable(text: $query, prompt: "Collection name or notes")
        .toolbar { ToolbarItem(placement: .primaryAction) {
            Button("New collection", systemImage: "plus") { creating = true }.accessibilityIdentifier("newCollectionButton")
        } }
        .sheet(isPresented: $creating) { NavigationStack { CollectionEditor(collection: MailCollection(name: "")) } }
    }
}

struct CollectionEditor: View {
    @State var collection: MailCollection
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    var body: some View {
        Form {
            TextField("Collection name", text: $collection.name).accessibilityIdentifier("collectionNameField")
            Section("Notes") { TextEditor(text: $collection.notes).frame(minHeight: 120) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Collection").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        guard let repository = runtime.repository else { throw GmailError.reconnect }
                        // Preserve membership changed since this editor opened.
                        if let row = try repository.metadata(collection.key) { collection.links = try MailCollection.decode(row).links }
                        try repository.saveCollection(collection); dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.accessibilityIdentifier("saveCollectionButton")
            }
        }
    }
}

struct AddToCollectionView: View {
    let message: MailMessage
    @Query private var metadata: [StoreMetadata]
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var errorMessage: String?
    private var collections: [MailCollection] {
        metadata.filter { $0.key.hasPrefix(MailCollection.prefix) }.compactMap { try? MailCollection.decode($0) }.sorted { $0.name < $1.name }
    }
    var body: some View {
        List {
            Section { Text(message.subject).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(collections) { collection in
                let included = collection.links.contains { $0.contains(message) }
                Button {
                    do {
                        guard let repository = runtime.repository else { throw GmailError.reconnect }
                        var updated = collection
                        updated.links.append(MailCollectionLink(message)); try repository.saveCollection(updated); dismiss()
                    } catch { errorMessage = error.localizedDescription }
                } label: { Label(collection.name, systemImage: included ? "checkmark.circle.fill" : "folder") }
                    .disabled(included)
            }
            Button("New collection", systemImage: "folder.badge.plus") { creating = true }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Add to collection").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $creating) {
            NavigationStack { CollectionEditor(collection: MailCollection(name: "", links: [MailCollectionLink(message)])) }
        }
    }
}
