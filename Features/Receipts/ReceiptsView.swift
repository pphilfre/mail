import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts

struct ReceiptEditContext: Identifiable {
    var id: UUID { source.id }
    let source: ReceiptSource
    let detected: ReceiptSummary?
    let correction: ReceiptOverride?
}

struct ReceiptsView: View {
    let accountID: UUID?
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    @Query private var metadata: [StoreMetadata]
    @Query private var accounts: [MailAccount]
    @State private var detected: [UUID: ReceiptSummary] = [:]
    @State private var scanning = true
    private var sources: [ReceiptSource] {
        messages.filter { !$0.isTrash && !$0.isSpam && !$0.isDraft && !$0.isSent && (accountID == nil || $0.accountID == accountID) }
            .map(ReceiptSource.init)
    }
    private var corrections: [String: ReceiptOverride] {
        Dictionary(uniqueKeysWithValues: metadata.filter { $0.key.hasPrefix("receipt-override:") }.compactMap {
            guard let value = try? ReceiptOverride.decode($0) else { return nil }
            return ($0.key, value)
        })
    }
    private var allReceipts: [ReceiptSummary] {
        let overrides = corrections
        return sources.compactMap { source in
            let result: ReceiptSummary?
            if let value = overrides[ReceiptOverride.prefix(source.accountID) + source.remoteID] {
                result = value.apply(to: source, detected: detected[source.id])
            } else { result = detected[source.id] }
            return result
        }
    }
    var body: some View {
        let snapshot = sources
        ReceiptResultsView(accountID: accountID, messages: messages, metadata: metadata, accounts: accounts,
            detected: detected, scanning: scanning, sources: snapshot, corrections: corrections, allReceipts: allReceipts)
        .task(id: snapshot) {
            scanning = true
            let work = Task.detached(priority: .userInitiated) {
                var result: [ReceiptSummary] = []
                for source in snapshot {
                    if Task.isCancelled { break }
                    if let receipt = ReceiptDetector.detect(source) { result.append(receipt) }
                }
                return result
            }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            detected = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) }); scanning = false
        }
    }
}

private struct ReceiptResultsView: View {

    let accountID: UUID?
    @Environment(AppRuntime.self) private var runtime
    let messages: [MailMessage]
    let metadata: [StoreMetadata]
    let accounts: [MailAccount]
    let detected: [UUID: ReceiptSummary]
    let scanning: Bool
    @State private var query = ""
    @State private var thisMonth = false
    @State private var kindFilter = "All"
    @State private var flowFilter: ReceiptFlow?
    @State private var unknownOnly = false
    @State private var editing: ReceiptEditContext?
    @State private var errorMessage: String?
    @State private var exporting = false
    @State private var selectedReceipt: ReceiptSummary?
    @State private var showingReceipt = false
    let sources: [ReceiptSource]
    let corrections: [String: ReceiptOverride]
    private func correction(_ source: ReceiptSource) -> ReceiptOverride? {
        corrections[ReceiptOverride.prefix(source.accountID) + source.remoteID]
    }
    let allReceipts: [ReceiptSummary]
    private var receipts: [ReceiptSummary] {
        allReceipts.filter { result in
            if kindFilter != "All" && result.kind != kindFilter { return false }
            if let flowFilter, result.flow != flowFilter { return false }
            if unknownOnly && result.money != nil { return false }
            if thisMonth && !Calendar.current.isDate(result.receivedAt, equalTo: Date(), toGranularity: .month) { return false }
            let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !search.isEmpty && ![result.merchant, result.subject, result.senderEmail, result.money?.display ?? ""]
                .contains(where: { $0.localizedCaseInsensitiveContains(search) }) { return false }
            return true
        }
    }
    var body: some View {
        let visible = receipts
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visible) { calendar.dateInterval(of: .month, for: $0.receivedAt)?.start ?? $0.receivedAt }
        let months = groups.keys.sorted(by: >)
        List {
            Section {
                ReceiptCashFlowView(receipts: visible)
                    .padding(16).background(MailStyle.tile.opacity(0.6), in: .rect(cornerRadius: 22))
                    .listRowSeparator(.hidden)
            }.listRowBackground(MailStyle.paper)
            if scanning {
                HStack { Spacer(); ProgressView().controlSize(.small).accessibilityLabel("Finding receipts"); Spacer() }
                    .listRowSeparator(.hidden).listRowBackground(MailStyle.paper)
            }
            ForEach(months, id: \.self) { month in
                Section(month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(groups[month] ?? []) { receipt in
                        Button { selectedReceipt = receipt; showingReceipt = true } label: {
                            receiptRow(receipt).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                        }
                            .buttonStyle(.plain).listRowBackground(MailStyle.paper)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                            .accessibilityIdentifier("receipt-\(receipt.remoteID)")
                            .contextMenu {
                                Button("Review receipt", systemImage: "pencil") { edit(receipt) }
                                Button("Exclude from Receipts", systemImage: "eye.slash") { exclude(receipt) }
                            }
                    }
                }
            }
            if !scanning && visible.isEmpty {
                ContentUnavailableView("No receipts found", systemImage: "receipt", description: Text("Receipt and invoice emails appear here as mail downloads. You can also open any message and choose Save receipt."))
            }
            if metadata.contains(where: { $0.key.hasPrefix(accountID.map(ReceiptOverride.prefix) ?? "receipt-override:") && (try? ReceiptOverride.decode($0)) == nil }) {
                Text(ReceiptError.invalidData.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .modifier(MailWorkspaceList())
        .environment(\.editMode, .constant(.inactive))
        .navigationDestination(isPresented: $showingReceipt) {
            if let selectedReceipt {
                ReceiptDetailView(receipt: selectedReceipt, history: allReceipts, message: messages.first { $0.id == selectedReceipt.id }, onEdit: { edit(selectedReceipt) })
            }
        }
        .navigationTitle("Receipts").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search receipts")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .toolbar {
            ToolbarItem(placement: .principal) { MailNavigationTitle(title: "Receipts") }
            ToolbarItem(placement: .topBarLeading) {
                Menu("Filter transactions", systemImage: "line.3.horizontal.decrease") {
                    Toggle("This month", isOn: $thisMonth)
                    Picker("Type", selection: $kindFilter) {
                        Text("All").tag("All"); Text("Receipts").tag("Receipt"); Text("Invoices").tag("Invoice")
                    }
                    Picker("Direction", selection: $flowFilter) {
                        Text("All").tag(ReceiptFlow?.none)
                        ForEach(ReceiptFlow.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    Toggle("Unknown amounts", isOn: $unknownOnly)
                    Button("Reset filters") { thisMonth = false; kindFilter = "All"; flowFilter = nil; unknownOnly = false }
                }.accessibilityIdentifier("receiptFilters")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Export CSV", systemImage: "square.and.arrow.up") { exporting = true }
                    .disabled(receipts.isEmpty || scanning)
            }
        }
        .fileExporter(isPresented: $exporting, document: ReceiptCSVDocument(text: ReceiptExport.csv(receipts,
            accountNames: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.email) }))), contentType: .commaSeparatedText, defaultFilename: "Dispatch receipts") {
            if case .failure(let error) = $0 { errorMessage = error.localizedDescription }
        }
        .sheet(item: $editing) { context in NavigationStack { ReceiptEditor(context: context) } }
    }
    private func receiptRow(_ receipt: ReceiptSummary) -> some View {
        HStack(spacing: 12) {
            SenderAvatar(email: receipt.senderEmail, name: receipt.merchant, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.merchant).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(receipt.receivedAt, format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(MailStyle.secondaryInk)
            }
            Spacer(minLength: 8)
            Text(receipt.signedAmount).font(.body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(receipt.flow.color).lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel(receipt.money == nil ? "Amount unknown" : receipt.signedAmount)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
    private func edit(_ receipt: ReceiptSummary) {
        if let source = sources.first(where: { $0.id == receipt.id }) {
            editing = ReceiptEditContext(source: source, detected: detected[source.id], correction: correction(source))
        }
    }
    private func exclude(_ receipt: ReceiptSummary) {
        var value = corrections[ReceiptOverride.prefix(receipt.accountID) + receipt.remoteID] ?? ReceiptOverride(accountID: receipt.accountID, remoteID: receipt.remoteID)
        value.inclusion = "exclude"
        do { try runtime.repository?.saveReceipt(value) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct ReceiptDetailView: View {
    let receipt: ReceiptSummary
    let history: [ReceiptSummary]
    let message: MailMessage?
    let onEdit: () -> Void
    @Query private var metadata: [StoreMetadata]
    private var current: ReceiptSummary {
        guard let message, let row = metadata.first(where: { $0.key == ReceiptOverride.prefix(receipt.accountID) + receipt.remoteID }),
              let value = try? ReceiptOverride.decode(row) else { return receipt }
        return value.apply(to: ReceiptSource(message), detected: receipt) ?? receipt
    }
    var body: some View {
        let receipt = current
        Form {
            Section {
                HStack(spacing: 12) {
                    SenderAvatar(email: receipt.senderEmail, name: receipt.merchant, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.merchant).font(.title2.weight(.semibold))
                        Label(receipt.flow.title, systemImage: receipt.flow == .incoming ? "arrow.down.left" : receipt.flow == .outgoing ? "arrow.up.right" : "questionmark.circle")
                            .font(.subheadline).foregroundStyle(receipt.flow.color)
                    }
                }
                Text(receipt.signedAmount).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(receipt.flow.color)
                LabeledContent("Type", value: receipt.kind)
                LabeledContent("Received", value: receipt.receivedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if !receipt.facts.isEmpty {
                Section("Transaction details") {
                    ForEach(receipt.facts) { fact in LabeledContent(fact.label, value: fact.value).textSelection(.enabled) }
                }
            }
            Section("Activity with " + receipt.merchant) {
                ReceiptCashFlowView(receipts: history.filter { $0.merchant == receipt.merchant }.map { $0.id == receipt.id ? receipt : $0 })
            }
            Section("Source") {
                if let message { NavigationLink("Open original email") { GmailMessageView(message: message) } }
            }
        }
        .modifier(MailWorkspaceList())
        .mailSheetTitle("Receipt")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Review", action: onEdit).accessibilityIdentifier("reviewReceiptButton") } }
    }
}

struct ReceiptEditor: View {
    let context: ReceiptEditContext
    @Environment(AppRuntime.self) private var runtime
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @State private var merchant: String
    @State private var amount: String
    @State private var currency: String
    @State private var included: Bool
    @State private var flow: ReceiptFlow
    @State private var kind: String
    @State private var errorMessage: String?
    init(context: ReceiptEditContext) {
        self.context = context
        let money = context.correction?.amountReviewed == true ? context.correction?.money : context.detected?.money
        _merchant = State(initialValue: context.correction?.merchant ?? context.detected?.merchant ?? ReceiptDetector.merchant(context.source))
        _amount = State(initialValue: money.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _currency = State(initialValue: money?.currency ?? "GBP")
        _included = State(initialValue: context.correction?.inclusion != "exclude")
        _kind = State(initialValue: context.correction?.kind ?? context.detected?.kind ?? "Receipt")
        _flow = State(initialValue: context.correction?.flow ?? context.detected?.flow ?? .unknown)
    }
    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    Text("Receipt").tag("Receipt"); Text("Invoice").tag("Invoice")
                }.accessibilityIdentifier("receiptType")
                LabeledContent("Merchant") { TextField("Name", text: $merchant).multilineTextAlignment(.trailing).accessibilityIdentifier("receiptMerchant") }
                LabeledContent("Amount") { TextField("?", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("receiptAmount") }
                LabeledContent("Currency") { TextField("GBP", text: $currency).textInputAutocapitalization(.characters).autocorrectionDisabled().multilineTextAlignment(.trailing) }
                Picker("Direction", selection: $flow) { ForEach(ReceiptFlow.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("Include in Receipts", isOn: $included)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .modifier(MailWorkspaceList())
        .navigationTitle("Review receipt").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { MailNavigationTitle(title: "Review receipt") } }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save receipt", action: save).accessibilityIdentifier("saveReceiptButton")
            }
        }
    }
    private func save() {
        var value = ReceiptOverride(accountID: context.source.accountID, remoteID: context.source.remoteID)
        value.inclusion = included ? "include" : "exclude"
        value.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.merchant?.isEmpty == true { value.merchant = ReceiptDetector.merchant(context.source) }
        value.amountReviewed = true
        value.flow = flow
        value.kind = kind
        let input = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            guard let decimal = ReceiptDetector.enteredAmount(input) else { errorMessage = ReceiptError.invalidAmount.localizedDescription; return }
            value.money = ReceiptMoney(amount: decimal, currency: currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        }
        do { try runtime.repository?.saveReceipt(value); feedback.show("Receipt saved", symbol: "receipt"); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct ReceiptCSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    let text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

enum ReceiptExport {
    static func csv(_ receipts: [ReceiptSummary], accountNames: [UUID: String] = [:]) -> String {
        func cell(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = trimmed.first.map { "=+-@".contains($0) } == true ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = receipts.map { receipt in
            [receipt.receivedAt.ISO8601Format(), accountNames[receipt.accountID] ?? "", receipt.merchant, receipt.kind,
             receipt.money.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "",
             receipt.money?.currency ?? "", receipt.subject, receipt.senderEmail, receipt.reviewed ? "Reviewed" : "Detected", receipt.flow.title].map(cell).joined(separator: ",")
        }
        return (["Date,Account,Merchant,Type,Amount,Currency,Subject,Sender,Status,Direction"] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
