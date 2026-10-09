import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppRuntime {
    let connectivity = NetworkConnectivity()
    let draftAttachments = DraftAttachmentStore()
    let appLock = MailAppLock()
    let localModel = LocalMailModel()
    var sharedDraft: LocalDraft?
    var shareError: String?
    @ObservationIgnored private var pendingShares: [URL] = []
    @ObservationIgnored private var importingShare = false
    let reputation = VirusTotalReputation()
    var securityReports: [UUID: (fingerprint: String, report: SecurityReport)] = [:]
    var container: ModelContainer?
    var session: AppSession?
    var storageFailed = false
    var gmail: GmailCoordinator?
    @ObservationIgnored var repository: MailRepository?
    #if DEBUG
    private static var seededUITestPreferences = false
    #endif

    init() {
        #if DEBUG
        // Seed the normal preferences domain so UI tests can change it after launch.
        if !Self.seededUITestPreferences, let sampleInbox = ProcessInfo.processInfo.environment["DISPATCH_UI_TEST_SAMPLE_INBOX"] {
            Self.seededUITestPreferences = true
            UserDefaults.standard.set(sampleInbox == "YES", forKey: "showSampleInbox")
            UserDefaults.standard.set("Inbox", forKey: "selectedMailbox")
            UserDefaults.standard.set("", forKey: "selectedMailAccount")
            UserDefaults.standard.set(true, forKey: "conversationRows")
            UserDefaults.standard.set(false, forKey: "compactInbox")
            UserDefaults.standard.set(2, forKey: "previewLines")
            UserDefaults.standard.set("", forKey: "defaultSendingAccount")
            UserDefaults.standard.set("[]", forKey: "recentMailSearches")
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
            if !readerFixture {
                try LocalMailProtection.protectTree(URL.applicationSupportDirectory.appending(path: "Mail/Attachments"))
                try LocalMailProtection.protectTree(URL.applicationSupportDirectory.appending(path: "Dispatch/DraftAttachments"))
                try AttachmentPreviewStore.cleanExpired()
            }
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
            self.gmail = readerFixture ? nil : GmailCoordinator(repository: repository, draftAttachments: draftAttachments)
            #if DEBUG
            if ProcessInfo.processInfo.environment["DISPATCH_UI_TEST_DRAFT_ATTACHMENT"] == "YES" {
                let fixtureID = UUID(uuidString: "C0626EB5-478F-4272-BD4E-C102B61EB052")!
                if !session.drafts.contains(where: { $0.id == fixtureID }) {
                    Task { @MainActor in
                        do {
                            var draft = LocalDraft(id: fixtureID, subject: "Attachment test draft", body: "Keep this body")
                            let item = try await draftAttachments.store(Data("Fixture attachment".utf8), filename: "fixture.txt",
                                mimeType: "text/plain", draftID: draft.id, existing: [])
                            draft.attachments = [item]; try session.save(draft)
                        } catch { session.storageError = error.localizedDescription }
                    }
                }
            }
            #endif
            let savedPaths = Set(try container.mainContext.fetch(FetchDescriptor<MailAttachment>()).compactMap(\.cachedRelativePath))
            if let cache = gmail?.attachmentCache { Task { try? await cache.prune(keeping: savedPaths) } }
            let draftIDs = Set(try container.mainContext.fetch(FetchDescriptor<OutgoingMessage>()).map(\.id))
            Task { try? await draftAttachments.prune(keeping: draftIDs) }
            storageFailed = false
        } catch {
            // No destructive reset, in-memory replacement or network fetch on storage failure.
            container = nil; repository = nil; session = nil; gmail = nil; storageFailed = true
        }
    }

    func receiveShare(_ url: URL) {
        guard IncomingMailShare.parse(url) != nil, pendingShares.count < 20 else { return }
        pendingShares.append(url)
        Task { await importPendingShares() }
    }

    func importPendingShares() async {
        guard appLock.unlocked, !importingShare, sharedDraft == nil, let session else { return }
        importingShare = true
        defer { importingShare = false }
        while appLock.unlocked, !pendingShares.isEmpty {
            let url = pendingShares.removeFirst()
            guard let incoming = IncomingMailShare.parse(url) else { continue }
            do {
                var draft = LocalDraft()
                switch incoming {
                case .file(let source):
                    draft.attachments = [try await draftAttachments.importFile(source, draftID: draft.id, existing: [])]
                case .link(let link): draft.body = link.absoluteString
                case .compose(let to, let subject, let body): draft.to = to; draft.subject = subject; draft.body = body
                }
                try session.save(draft)
                if appLock.unlocked { sharedDraft = draft }
                return
            } catch { shareError = error.localizedDescription }
        }
    }
}
