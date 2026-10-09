import SwiftUI
import SwiftData

struct LocalWritingView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let text: String
    let tasks: [LocalWritingTask]
    var apply: ((String) -> Void)?
    @State private var selected: LocalWritingTask
    @State private var output = ""
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    @State private var running = false
    init(text: String, tasks: [LocalWritingTask], apply: ((String) -> Void)? = nil) {
        self.text = text; self.tasks = tasks; self.apply = apply
        _selected = State(initialValue: tasks.first ?? .summary)
    }
    var body: some View {
        Form {
            Section {
                Picker("Help with", selection: $selected) { ForEach(tasks) { Text($0.rawValue).tag($0) } }.disabled(running)
                if !runtime.localModel.installed { Text("Download the optional local writing model in Settings. No mail is sent to a model service.") }
                Button(running ? "Working on this device…" : "Generate suggestion") {
                    running = true; output = ""; error = nil
                    job = Task {
                        defer { running = false }
                        do { output = try await runtime.localModel.generate(selected, text: text) }
                        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                    }
                }.disabled(running || runtime.localModel.busy || !runtime.localModel.installed || !LocalModelWorker.supported || text.isEmpty)
                if running { Button("Cancel") { job?.cancel() } }
                if let error { Text(error).foregroundStyle(.secondary) }
            } footer: { Text("Uses up to 4,000 characters and 192 output tokens. Suggestions may be incomplete or inaccurate; review before using.") }
            if !output.isEmpty {
                Section("Suggestion · generated locally") {
                    Text(output).textSelection(.enabled)
                    if let apply { Button("Use in draft") { apply(output); dismiss() } }
                    ShareLink(item: output) { Label("Share text", systemImage: "square.and.arrow.up") }
                }
            }
        }.navigationTitle("Writing assistance").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onDisappear { job?.cancel() }
    }
}

struct MailInsightsView: View {
    let mails: [IntelligenceMail]
    @Environment(\.dismiss) private var dismiss
    @State private var summaries: [UUID: [String]] = [:]
    @State private var dates: [UUID: [ExtractedMailDate]] = [:]
    @State private var categories: [UUID: LocalMailCategory] = [:]
    @State private var writing = false
    var body: some View {
        List {
            Section {
                Text("Selected sentences from cached mail. Missing bodies use previews; this may omit context. Explicit dates and today/tomorrow relative to the email’s received date are shown for review.").font(.caption).foregroundStyle(.secondary)
                Button("Generate a thread summary", systemImage: "text.bubble") { writing = true }
            }
            ForEach(mails.suffix(30)) { mail in
                Section(mail.sender) {
                    LabeledContent("Suggested category", value: categories[mail.id]?.rawValue ?? "…")
                    ForEach(Array((summaries[mail.id] ?? []).enumerated()), id: \.offset) { _, text in Text(text).textSelection(.enabled) }
                    ForEach(dates[mail.id] ?? []) { value in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(value.isDeadline ? "Possible deadline: " + value.phrase : value.phrase, systemImage: "calendar")
                            Text(value.context).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("Local insights")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $writing) {
            NavigationStack { LocalWritingView(text: mails.suffix(10).map { $0.sender + ": " + $0.text }.joined(separator: "\n"), tasks: [.summary]) }
        }
        .task(id: mails) {
            let snapshot = Array(mails.suffix(30))
            let work = Task.detached(priority: .utility) {
                var summaries: [UUID: [String]] = [:]; var dates: [UUID: [ExtractedMailDate]] = [:]
                var categories: [UUID: LocalMailCategory] = [:]
                for mail in snapshot {
                    if Task.isCancelled { break }
                    summaries[mail.id] = LocalMailAnalysis.summary(mail.text, subject: mail.subject)
                    dates[mail.id] = LocalMailAnalysis.dates(mail.text, referenceDate: mail.receivedAt); categories[mail.id] = LocalMailAnalysis.category(mail)
                }
                return (summaries, dates, categories)
            }
            let values = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            summaries = values.0; dates = values.1; categories = values.2
        }
    }
}

struct LocalMailOverview: View {
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    let accountID: UUID?
    let catchUp: Bool
    @State private var category: LocalMailCategory?
    @State private var results: [IntelligenceMail] = []
    @State private var categories: [UUID: LocalMailCategory] = [:]
    @State private var excerpts: [UUID: String] = [:]
    @State private var preparing = true
    private var snapshots: [IntelligenceMail] {
        messages.lazy.filter { !$0.isSpam && !$0.isTrash && !$0.isDraft && !$0.isSent && (accountID == nil || $0.accountID == accountID) }
            .prefix(catchUp ? 300 : 1_000).map { IntelligenceMail($0, includeBody: false) }
    }
    var body: some View {
        let snapshot = snapshots
        List {
            Section {
                Text(catchUp ? "Important unread threads ranked by stars, provider importance and local action-word hints. Summaries use cached previews; open a thread for body insights." : "Local suggestions based on provider labels and preview text hints. Provider folders are unchanged.").font(.caption).foregroundStyle(.secondary)
                if !catchUp {
                    Picker("Category", selection: $category) {
                        Text("All").tag(LocalMailCategory?.none)
                        ForEach(LocalMailCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }
            }
            if preparing { ProgressView("Analysing cached mail…") }
            ForEach(results.filter { category == nil || categories[$0.id] == category }) { mail in
                if let message = messages.first(where: { $0.id == mail.id }) {
                    NavigationLink { GmailMessageView(message: message) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mail.subject.isEmpty ? "No subject" : mail.subject).font(.headline)
                            Text(mail.sender).font(.subheadline).foregroundStyle(.secondary)
                            Text(excerpts[mail.id] ?? "").font(.callout).lineLimit(4)
                            Text(categories[mail.id]?.rawValue ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !preparing && results.isEmpty { ContentUnavailableView(catchUp ? "No important unread mail in this cache" : "No cached mail", systemImage: "tray") }
            Text(catchUp ? "Examines the latest 300 cached messages; shows up to 20 threads." : "Examines the latest 1,000 cached messages.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle(catchUp ? "Catch up" : "Local categories")
        .task(id: snapshot) {
            preparing = true
            let scope = accountID; let catchUp = catchUp
            let work = Task.detached(priority: .utility) {
                let rows = catchUp ? LocalMailAnalysis.catchUp(snapshot, accountID: scope) : snapshot
                var labels: [UUID: LocalMailCategory] = [:]; var excerpts: [UUID: String] = [:]
                for mail in rows {
                    if Task.isCancelled { break }
                    labels[mail.id] = LocalMailAnalysis.category(mail)
                    excerpts[mail.id] = LocalMailAnalysis.summary(mail.text, subject: mail.subject, limit: 1).first ?? ""
                }
                return (rows, labels, excerpts)
            }
            let values = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            results = values.0; categories = values.1; excerpts = values.2; preparing = false
        }
    }
}

struct MailIntegrationSettings: View {
    @Environment(AppRuntime.self) private var runtime
    @AppStorage("mailAppLock") private var locked = false
    var body: some View {
        Form {
            Section {
                Toggle("Face ID app lock", isOn: Binding(get: { locked }, set: { enabled in Task { await runtime.appLock.setEnabled(enabled) } })).disabled(runtime.appLock.authenticating)
                if let error = runtime.appLock.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            } footer: { Text("Authenticates before enabling or disabling. Locks after backgrounding; device passcode recovers from biometric lockout. Mail is hidden from app-switcher snapshots.") }
            Section("Optional local writing model") {
                Text("Qwen3 0.6B · 4-bit · approximately 347 MB").font(.headline)
                Text("Downloads over Wi-Fi from Hugging Face. Generation runs offline on this device. No email is uploaded. Requires a physical iPhone with at least 6 GB RAM, including iPhone 14 Pro Max.").font(.caption).foregroundStyle(.secondary)
                if runtime.localModel.installed {
                    Button("Delete downloaded model", role: .destructive) { Task { await runtime.localModel.delete() } }.disabled(runtime.localModel.busy)
                } else {
                    Button("Download model over Wi-Fi") { Task { await runtime.localModel.download() } }.disabled(runtime.localModel.busy || !LocalModelWorker.supported)
                }
                if runtime.localModel.busy { ProgressView(); Button("Cancel model task") { runtime.localModel.cancel() } }
                if let status = runtime.localModel.status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Section("LiveContainer compatibility") {
                Text("Interactive Home and Lock Screen widgets and a Dispatch Share extension need separately installed extension processes. LiveContainer cannot register guest extensions.")
                Text("Siri/App Intents, Spotlight and account Focus Filters depend on system registration of Dispatch. This guest build does not advertise or index them under LiveContainer’s identity.")
                Text("Remote actionable push notifications require an APNs entitlement, a registered app and a mail push delivery service. LiveContainer guests cannot receive remote push.")
                Text("For files and links, choose LiveContainer in the system Share Sheet, then Dispatch. Forwarded content opens a saved draft for review. HTTP links can also use LiveContainer’s URL launcher. A direct Dispatch Share extension is unavailable.")
                Text("LiveContainer’s Launch App shortcut can launch Dispatch; email actions in Siri and Shortcuts are unavailable. Use the inbox’s account selector for manual filtering.")
            }.font(.callout)
        }.navigationTitle("Privacy & intelligence").navigationBarTitleDisplayMode(.inline)
    }
}
