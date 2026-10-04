import Foundation
import Observation

/// Stage-one presentation state. Sample messages are never connected to a provider.
@MainActor
@Observable
final class AppSession {
    var sampleMessages = SampleMessage.examples
    var drafts: [LocalDraft]
    var storageError: String?
    @ObservationIgnored private let draftStore: any DraftPersistence

    init(draftStore: any DraftPersistence = DraftStore()) {
        self.draftStore = draftStore
        do {
            drafts = try draftStore.load()
        } catch {
            drafts = []
            storageError = "Saved drafts could not be opened. Your draft file has been kept."
        }
    }

    func save(_ draft: LocalDraft) throws {
        // Never overwrite an unreadable draft file with an empty replacement.
        guard storageError == nil else { throw DraftStoreError.unreadableStore }
        // Provider draft imports and send state changes can occur after this session last loaded.
        var updated = try draftStore.load()
        if let index = updated.firstIndex(where: { $0.id == draft.id }) {
            updated[index] = draft
        } else {
            updated.insert(draft, at: 0)
        }
        try draftStore.save(updated)
        drafts = updated
    }

    func deleteDraft(at offsets: IndexSet) throws {
        guard storageError == nil else { throw DraftStoreError.unreadableStore }
        let ids = Set(drafts.enumerated().filter { offsets.contains($0.offset) }.map { $0.element.id })
        let updated = try draftStore.load().filter { !ids.contains($0.id) }
        try draftStore.save(updated)
        drafts = updated
    }

    func deleteDraft(id: UUID) throws {
        guard storageError == nil else { throw DraftStoreError.unreadableStore }
        let updated = try draftStore.load().filter { $0.id != id }
        try draftStore.save(updated)
        drafts = updated
    }

    func markSampleRead(_ id: UUID) {
        guard let index = sampleMessages.firstIndex(where: { $0.id == id }) else { return }
        sampleMessages[index].isRead = true
    }

    func reloadDrafts() throws { drafts = try draftStore.load() }
}
