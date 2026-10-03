import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppRuntime {
    var container: ModelContainer?
    var session: AppSession?
    var storageFailed = false
    var gmail: GmailCoordinator?
    @ObservationIgnored var repository: MailRepository?

    init() { openStorage() }

    func openStorage() {
        do {
            let container = try MailStorage.open()
            let repository = MailRepository(context: container.mainContext)
            try repository.migrateFoundationDrafts(from: DraftStore())
            try repository.recoverInterruptedSends()
            let session = AppSession(draftStore: repository)
            guard session.storageError == nil else { throw DraftStoreError.unreadableStore }
            self.container = container
            self.repository = repository
            self.session = session
            self.gmail = GmailCoordinator(repository: repository)
            storageFailed = false
        } catch {
            // No destructive reset, in-memory replacement or network fetch on storage failure.
            container = nil; repository = nil; session = nil; gmail = nil; storageFailed = true
        }
    }
}
