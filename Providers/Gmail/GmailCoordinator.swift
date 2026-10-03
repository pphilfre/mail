import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class GmailCoordinator {
    var connecting = false
    var syncing: Set<UUID> = []
    var writing: Set<UUID> = []
    var error: String?
    @ObservationIgnored let repository: MailRepository
    @ObservationIgnored let vault: CredentialVault
    @ObservationIgnored let transport: any MailHTTPTransport
    @ObservationIgnored private let signIn = GoogleSignIn()
    @ObservationIgnored private var managers: [UUID: GmailAPI] = [:]
    @ObservationIgnored private var refreshAgain: Set<UUID> = []
    init(repository: MailRepository, vault: CredentialVault = CredentialVault(), transport: any MailHTTPTransport = URLSessionMailTransport()) {
        self.repository = repository; self.vault = vault; self.transport = transport
    }
    func client(_ id: UUID) throws -> GmailAPI {
        if let api = managers[id] { return api }
        let tokens = GoogleTokenManager(configuration: try GoogleConfiguration.load(), vault: vault, transport: transport)
        let api = GmailAPI(transport: transport) { force in try await tokens.token(for: id, force: force) }
        managers[id] = api
        return api
    }
    func connect() async {
        guard !connecting else { return }
        connecting = true; error = nil
        defer { connecting = false }
        do {
            let credentials = try await signIn.connect(configuration: GoogleConfiguration.load(), transport: transport)
            let temporary = GmailAPI(transport: transport) { _ in credentials.accessToken }
            let profile = try await temporary.profile()
            guard MailMIME.valid(profile.emailAddress) else { throw GmailError.invalidResponse }
            let existing = try repository.accounts().first { $0.identity == "gmail:\(profile.emailAddress.lowercased())" }
            let account = existing ?? MailAccount(provider: .gmail, email: profile.emailAddress)
            try await vault.save(credentials, for: account.id)
            if existing == nil { repository.context.insert(account) }
            do { try repository.context.save() }
            catch {
                if existing == nil { try? await vault.remove(for: account.id); repository.context.rollback() }
                throw error
            }
            managers[account.id] = nil
            await sync(account.id)
        } catch GmailError.cancelled { }
        catch { self.error = error.localizedDescription }
    }
    func syncAll() async {
        do { for account in try repository.accounts() where account.providerRaw == "gmail" { await sync(account.id) } }
        catch { self.error = error.localizedDescription }
    }
    func sync(_ id: UUID) async {
        guard !syncing.contains(id) else { refreshAgain.insert(id); return }
        syncing.insert(id)
        defer { syncing.remove(id) }
        repeat {
            refreshAgain.remove(id)
            do {
                guard let account = try repository.account(id: id) else { return }
                let api = try client(id)
                try await flush(id, api: api)
                try repository.saveLabels(try await api.labels(), accountID: id)
                if let history = account.historyID {
                    do { try await incremental(id, since: history, api: api) }
                    catch GmailError.http(404) { try await full(id, api: api) }
                } else { try await full(id, api: api) }
                account.lastSyncAt = Date(); account.lastSyncError = nil
                try repository.context.save()
            } catch {
                if let account = try? repository.account(id: id) { account.lastSyncError = error.localizedDescription; try? repository.context.save() }
                self.error = error.localizedDescription
                break
            }
        } while refreshAgain.contains(id)
    }
    private func fetch(_ ids: Set<String>, accountID: UUID, api: GmailAPI) async throws -> (messages: [GmailMessageDTO], deleted: Set<String>) {
        var messages: [GmailMessageDTO] = []; var deleted: Set<String> = []
        // Bounded memory and request concurrency; bodies never enter logs.
        for id in ids.sorted() {
            do { messages.append(try await api.message(id)) }
            catch GmailError.http(404) { deleted.insert(id) }
            if messages.count == 20 { try repository.apply(messages, deleted: deleted, accountID: accountID); messages = []; deleted = [] }
        }
        return (messages, deleted)
    }
    private func full(_ id: UUID, api: GmailAPI) async throws {
        let baseline = try await api.profile().historyId
        let page = try await api.messages()
        let inbox = try await api.messages(label: "INBOX")
        let cached = try repository.recentMessages(accountID: id, limit: Int.max).map(\.remoteID)
        let ids = Set((page.messages ?? []).map(\.id) + (inbox.messages ?? []).map(\.id) + cached)
        let result = try await fetch(ids, accountID: id, api: api)
        try repository.apply(result.messages, deleted: result.deleted, accountID: id)
        // Capture the baseline before fetching. Drain changes that arrived during initial sync.
        try await incremental(id, since: baseline, api: api)
        if let account = try repository.account(id: id) { account.syncCursor = page.nextPageToken; try repository.context.save() }
    }
    private func incremental(_ id: UUID, since: String, api: GmailAPI) async throws {
        var pageToken: String?
        repeat {
            let page = try await api.history(since: since, page: pageToken)
            let result = try await fetch(page.changedIDs.subtracting(page.deletedIDs), accountID: id, api: api)
            // Keep the original cursor until all history pages commit successfully. Replay is idempotent.
            try repository.apply(result.messages, deleted: result.deleted.union(page.deletedIDs), accountID: id,
                historyID: page.nextPageToken == nil ? page.historyId : nil)
            pageToken = page.nextPageToken
        } while pageToken != nil
    }
    func loadOlder(_ id: UUID) async {
        guard !syncing.contains(id) else { return }
        syncing.insert(id)
        defer {
            syncing.remove(id)
            if refreshAgain.contains(id) { Task { await sync(id) } }
        }
        do {
            guard let account = try repository.account(id: id), let cursor = account.syncCursor else { return }
            let api = try client(id); let page = try await api.messages(page: cursor)
            let result = try await fetch(Set((page.messages ?? []).map(\.id)), accountID: id, api: api)
            try repository.apply(result.messages, deleted: result.deleted, accountID: id)
            account.syncCursor = page.nextPageToken; try repository.context.save()
        } catch { self.error = error.localizedDescription }
    }
    func loadThread(_ message: MailMessage) async {
        do {
            let thread = try await client(message.accountID).thread(message.remoteThreadID)
            try repository.apply(thread.messages ?? [], accountID: message.accountID)
        } catch { self.error = error.localizedDescription }
    }
    func action(_ kind: String, message: MailMessage) {
        do { try repository.enqueue(kind, message: message); Task { await sync(message.accountID) } }
        catch { self.error = error.localizedDescription }
    }
    func loadMailbox(_ name: String, accountID: UUID? = nil, labelID: String? = nil) async {
        do {
            let accounts = try repository.accounts().filter { (accountID == nil || $0.id == accountID) && $0.providerRaw == "gmail" }
            for account in accounts {
                guard !syncing.contains(account.id) else { continue }
                syncing.insert(account.id)
                do {
                    let api = try client(account.id)
                    let label: String?
                    let query: String?
                    if let labelID { label = labelID; query = nil }
                    else {
                        switch name {
                        case "Inbox": label = "INBOX"; query = nil
                        case "Unread": label = "UNREAD"; query = nil
                        case "Starred": label = "STARRED"; query = nil
                        case "Sent": label = "SENT"; query = nil
                        case "Drafts": label = "DRAFT"; query = nil
                        case "Trash": label = "TRASH"; query = nil
                        case "Archive": label = nil; query = "-in:inbox -in:sent -in:drafts -in:trash -in:spam"
                        default: label = nil; query = nil
                        }
                    }
                    let page = try await api.messages(label: label, query: query)
                    let result = try await fetch(Set((page.messages ?? []).map(\.id)), accountID: account.id, api: api)
                    try repository.apply(result.messages, deleted: result.deleted, accountID: account.id)
                    syncing.remove(account.id)
                    if refreshAgain.contains(account.id) { await sync(account.id) }
                } catch { syncing.remove(account.id); throw error }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func flush(_ id: UUID, api: GmailAPI) async throws {
        let pending = try repository.context.fetch(FetchDescriptor<PendingMailOperation>(predicate: #Predicate { $0.accountID == id }, sortBy: [SortDescriptor(\.createdAt)]))
        for operation in pending {
            do {
                switch operation.kindRaw {
                case "read": try await api.modify(operation.targetRemoteID, remove: ["UNREAD"])
                case "unread": try await api.modify(operation.targetRemoteID, add: ["UNREAD"])
                case "star": try await api.modify(operation.targetRemoteID, add: ["STARRED"])
                case "unstar": try await api.modify(operation.targetRemoteID, remove: ["STARRED"])
                case "archive": try await api.modify(operation.targetRemoteID, remove: ["INBOX"])
                case "trash": try await api.trash(operation.targetRemoteID)
                case "restore": try await api.trash(operation.targetRemoteID, restore: true)
                default:
                    if operation.kindRaw.hasPrefix("labelAdd:") {
                        try await api.modify(operation.targetRemoteID, add: [String(operation.kindRaw.dropFirst(9))])
                    } else if operation.kindRaw.hasPrefix("labelRemove:") {
                        try await api.modify(operation.targetRemoteID, remove: [String(operation.kindRaw.dropFirst(12))])
                    } else { throw GmailError.invalidResponse }
                }
                repository.context.delete(operation); try repository.context.save()
            } catch GmailError.http(404) {
                try repository.apply([], deleted: [operation.targetRemoteID], accountID: id)
                repository.context.delete(operation); try repository.context.save()
            } catch {
                operation.attemptCount += 1; operation.lastError = error.localizedDescription
                try repository.context.save(); throw error
            }
        }
    }
    func saveRemoteDraft(_ draft: LocalDraft) async throws {
        guard let id = draft.accountID, let account = try repository.account(id: id), let row = try repository.outgoing(draft.id) else { throw GmailError.reconnect }
        guard row.stateRaw == "draft" else { throw GmailError.uncertainSend }
        guard !writing.contains(id) else { throw GmailError.busy }
        writing.insert(id); defer { writing.remove(id) }
        let raw = try MailMIME.raw(draft, from: account.email, requireRecipient: false)
        let api = try client(id)
        // Recover a previous ambiguous create by stable Message-ID before creating a new remote draft.
        var remoteID = row.remoteDraftID
        if remoteID == nil {
            let found = try await api.drafts(query: "rfc822msgid:\(row.internetMessageID)")
            remoteID = found.drafts?.first?.id
        }
        let remote = try await api.saveDraft(id: remoteID, raw: raw, threadID: draft.remoteThreadID)
        row.remoteDraftID = remote.id; try repository.context.save()
    }
    func importDraft(_ message: MailMessage) async throws -> LocalDraft {
        let accountID = message.accountID
        guard !writing.contains(accountID) else { throw GmailError.busy }
        writing.insert(accountID); defer { writing.remove(accountID) }
        let api = try client(message.accountID)
        var page: String?
        repeat {
            let drafts = try await api.drafts(page: page)
            if let reference = drafts.drafts?.first(where: { $0.message?.id == message.remoteID }) {
                if let existing = try repository.context.fetch(FetchDescriptor<OutgoingMessage>(predicate: #Predicate { $0.accountID == accountID && $0.stateRaw == "draft" }))
                    .first(where: { $0.remoteDraftID == reference.id }) { return existing.localDraft }
                let remote = try await api.draft(reference.id)
                guard try repository.account(id: accountID) != nil else { throw GmailError.reconnect }
                guard let dto = remote.message else { throw GmailError.invalidResponse }
                let header = dto.payload; let content = MailMIME.content(header)
                let draft = LocalDraft(to: header?.header("To") ?? "", cc: header?.header("Cc") ?? "", bcc: header?.header("Bcc") ?? "",
                    subject: MailMIME.decodedHeader(header?.header("Subject") ?? ""), body: content.text.isEmpty ? MailMIME.readableHTML(content.html) : content.text,
                    accountID: message.accountID, remoteThreadID: dto.threadId, inReplyTo: header?.header("In-Reply-To"), referencesHeader: header?.header("References"))
                let row = OutgoingMessage(draft: draft); row.remoteDraftID = reference.id
                repository.context.insert(row); try repository.context.save()
                return draft
            }
            page = drafts.nextPageToken
        } while page != nil
        throw GmailError.invalidResponse
    }
    func send(_ draft: LocalDraft) async throws {
        guard let id = draft.accountID, let account = try repository.account(id: id), let row = try repository.outgoing(draft.id) else { throw GmailError.reconnect }
        guard row.stateRaw == "draft" else { throw GmailError.uncertainSend }
        guard !writing.contains(id) else { throw GmailError.busy }
        writing.insert(id); defer { writing.remove(id) }
        let raw = try MailMIME.raw(draft, from: account.email)
        let api = try client(id)
        // Refresh before committing sending state so an expired credential cannot create an uncertain send.
        _ = try await api.profile()
        if let remoteID = row.remoteDraftID { _ = try await api.saveDraft(id: remoteID, raw: raw, threadID: draft.remoteThreadID) }
        row.stateRaw = "sending"; try repository.context.save()
        do {
            if let remoteID = row.remoteDraftID { _ = try await api.sendDraft(remoteID) }
            else { _ = try await api.send(raw: raw, threadID: draft.remoteThreadID) }
            row.stateRaw = "sent"; row.lastError = nil; try repository.context.save()
        } catch {
            // Explicit rejection is safe to edit/retry. Network/5xx/malformed success may already have sent mail.
            if let failure = error as? GmailError, case .http(let code) = failure, (400..<500).contains(code) {
                row.stateRaw = "draft"; row.lastError = failure.localizedDescription; try repository.context.save(); throw failure
            }
            row.stateRaw = "sendUnconfirmed"; row.lastError = GmailError.uncertainSend.localizedDescription
            try repository.context.save(); throw GmailError.uncertainSend
        }
        await sync(id)
    }
    func removeAccount(_ id: UUID) async {
        guard !syncing.contains(id), !writing.contains(id), !connecting else { throwRemovalBusy(); return }
        do {
            try await vault.remove(for: id)
            try repository.removeAccountData(id: id)
            managers[id] = nil
        } catch { self.error = error.localizedDescription }
    }
    private func throwRemovalBusy() { error = "Wait for this account’s current operation to finish before removing it." }

    func confirmSent(_ row: OutgoingMessage) async {
        guard let id = row.accountID else { return }
        do {
            let api = try client(id)
            let page = try await api.messages(query: "in:sent rfc822msgid:\(row.internetMessageID)")
            guard !(page.messages ?? []).isEmpty else {
                error = "No sent copy was found yet. Gmail search can take time to update; check Gmail before sending another copy."
                return
            }
            row.stateRaw = "sent"; row.lastError = nil; try repository.context.save()
            await sync(id)
        } catch { self.error = error.localizedDescription }
    }
}
