import SwiftUI
import SwiftData

struct LocalMailOverview: View {
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    let accountID: UUID?
    @State private var results: [IntelligenceMail] = []
    @State private var preparing = true
    private var snapshots: [IntelligenceMail] {
        messages.lazy.filter { !$0.isSpam && !$0.isTrash && !$0.isDraft && !$0.isSent && (accountID == nil || $0.accountID == accountID) }
            .prefix(300).map { IntelligenceMail($0, includeBody: false) }
    }
    var body: some View {
        let snapshot = snapshots
        let byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        List {
          Group {
            if preparing { ProgressView("Finding important unread mail…") }
            ForEach(results) { mail in
                if let message = byID[mail.id] {
                    NavigationLink { GmailMessageView(message: message) } label: { CachedMessageRow(message: message) }
                }
            }
            if !preparing && results.isEmpty {
                ContentUnavailableView("You’re caught up", systemImage: "checkmark.circle",
                    description: Text("No important unread conversations in downloaded mail."))
                    .listRowBackground(Color.clear)
            }
          }.listRowBackground(MailStyle.paper)
        }.listStyle(.plain).scrollContentBackground(.hidden).background(MailStyle.paper)
            .task(id: snapshot) {
                preparing = true
                let scope = accountID
                let work = Task.detached(priority: .utility) { LocalMailAnalysis.catchUp(snapshot, accountID: scope) }
                let rows = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
                guard !Task.isCancelled else { return }
                results = rows; preparing = false
            }
    }
}
