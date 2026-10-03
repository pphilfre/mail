import Foundation
import Observation

/// Stage-one presentation state. Sample messages are never connected to a provider.
@MainActor
@Observable
final class AppSession {
    var sampleMessages = SampleMessage.examples
    var drafts: [LocalDraft]
    var storageError: String?
    @ObservationIgnored private let draftStore: DraftStore

    init(draftStore: DraftStore = DraftStore()) {
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
        var updated = drafts
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
        let updated = drafts.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        try draftStore.save(updated)
        drafts = updated
    }

    func markSampleRead(_ id: UUID) {
        guard let index = sampleMessages.firstIndex(where: { $0.id == id }) else { return }
        sampleMessages[index].isRead = true
    }
}
