import Foundation
import Observation

/// A local checkpoint never uploads to Gmail. Discard restores the version opened by the user.
@MainActor
@Observable
final class DraftEditingSession {
    private let original: LocalDraft?
    private let id: UUID
    private var lastSavedInput: LocalDraft?
    var saved = false

    init(draft: LocalDraft, alreadySaved: Bool) {
        id = draft.id
        original = alreadySaved ? draft : nil
        lastSavedInput = alreadySaved ? draft : nil
        saved = alreadySaved
    }

    func isSaved(_ draft: LocalDraft) -> Bool { saved && draft == lastSavedInput }

    func checkpoint(_ draft: LocalDraft, session: AppSession) throws {
        guard draft.id == id else { return }
        guard draft != lastSavedInput else { return }
        if draft.isEmpty {
            try session.deleteDraft(id: id)
            saved = false
        } else {
            var snapshot = draft
            snapshot.updatedAt = Date()
            try session.save(snapshot)
            saved = true
        }
        lastSavedInput = draft
    }

    func discard(session: AppSession) throws {
        if let original { try session.save(original) }
        else { try session.deleteDraft(id: id) }
    }
}
