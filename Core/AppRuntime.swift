import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppRuntime {
    let connectivity = NetworkConnectivity()
    var container: ModelContainer?
    var session: AppSession?
    var storageFailed = false
    var gmail: GmailCoordinator?
    @ObservationIgnored var repository: MailRepository?

    init() {
        #if DEBUG
        // Seed the normal preferences domain so UI tests can change it after launch.
        if let sampleInbox = ProcessInfo.processInfo.environment["DISPATCH_UI_TEST_SAMPLE_INBOX"] {
            UserDefaults.standard.set(sampleInbox == "YES", forKey: "showSampleInbox")
            UserDefaults.standard.set("Inbox", forKey: "selectedMailbox")
            UserDefaults.standard.set("", forKey: "selectedMailAccount")
        }
        #endif
        openStorage()
    }

    func openStorage() {
        do {
            #if DEBUG
            let readerFixture = ReaderUITestFixture.enabled
            #else
            let readerFixture = false
            #endif
            let container = try MailStorage.open(inMemory: readerFixture)
            let repository = MailRepository(context: container.mainContext)
            #if DEBUG
            if readerFixture { try ReaderUITestFixture.seed(container.mainContext) }
            #endif
            if !readerFixture { try repository.migrateFoundationDrafts(from: DraftStore()) }
            try repository.recoverInterruptedSends()
            let session = AppSession(draftStore: repository)
            guard session.storageError == nil else { throw DraftStoreError.unreadableStore }
            self.container = container
            self.repository = repository
            self.session = session
            self.gmail = readerFixture ? nil : GmailCoordinator(repository: repository)
            let savedPaths = Set(try container.mainContext.fetch(FetchDescriptor<MailAttachment>()).compactMap(\.cachedRelativePath))
            if let cache = gmail?.attachmentCache { Task { try? await cache.prune(keeping: savedPaths) } }
            storageFailed = false
        } catch {
            // No destructive reset, in-memory replacement or network fetch on storage failure.
            container = nil; repository = nil; session = nil; gmail = nil; storageFailed = true
        }
    }
}
