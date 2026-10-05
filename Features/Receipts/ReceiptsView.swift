import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ReceiptEditContext: Identifiable {
    var id: UUID { source.id }
    let source: ReceiptSource
    let detected: ReceiptSummary?
    let correction: ReceiptOverride?
}

struct ReceiptsView: View {
    let accountID: UUID?
    @Environment(AppRuntime.self) private var runtime
    @Query(sort: \MailMessage.receivedAt, order: .reverse) private var messages: [MailMessage]
    @Query private var metadata: [StoreMetadata]
    @Query private var accounts: [MailAccount]
    @State private var detected: [UUID: ReceiptSummary] = [:]
    @State private var scanning = true
    @State private var query = ""
    @State private var thisMonth = false
    @State private var editing: ReceiptEditContext?
    @State private var errorMessage: String?
    @State private var exporting = false
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
    private func correction(_ source: ReceiptSource) -> ReceiptOverride? {
        corrections[ReceiptOverride.prefix(source.accountID) + source.remoteID]
    }
    private var receipts: [ReceiptSummary] {
        let overrides = corrections
        return sources.compactMap { source in
            let result: ReceiptSummary?
            if let value = overrides[ReceiptOverride.prefix(source.accountID) + source.remoteID] {
                result = value.apply(to: source, detected: detected[source.id])
            } else { result = detected[source.id] }
            guard let result else { return nil }
            if thisMonth && !Calendar.current.isDate(result.receivedAt, equalTo: Date(), toGranularity: .month) { return nil }
            let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !search.isEmpty && ![result.merchant, result.subject, result.senderEmail, result.money?.display ?? ""]
                .contains(where: { $0.localizedCaseInsensitiveContains(search) }) { return nil }
            return result
        }
    }
    private var months: [Date] {
        Array(Set(receipts.map { Calendar.current.dateInterval(of: .month, for: $0.receivedAt)?.start ?? $0.receivedAt })).sorted(by: >)
    }
    var body: some View {
        let snapshot = sources
        List {
            Section {
                Toggle("This month", isOn: $thisMonth)
                Text("\(receipts.count) receipts in downloaded mail").font(.caption).foregroundStyle(.secondary)
                Text("Amounts and merchant names are detected from email text. Open a receipt to review them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if scanning { ProgressView("Finding receipts…") }
            ForEach(months, id: \.self) { month in
                Section(month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(receipts.filter { Calendar.current.isDate($0.receivedAt, equalTo: month, toGranularity: .month) }) { receipt in
                        NavigationLink { ReceiptDetailView(receipt: receipt, message: messages.first { $0.id == receipt.id }, onEdit: { edit(receipt) }) }
                        label: { receiptRow(receipt) }
                            .accessibilityIdentifier("receipt-\(receipt.remoteID)")
                            .contextMenu {
                                Button("Review receipt", systemImage: "pencil") { edit(receipt) }
                                Button("Exclude from Receipts", systemImage: "eye.slash") { exclude(receipt) }
                            }
                    }
                }
            }
            if !scanning && receipts.isEmpty {
                ContentUnavailableView("No receipts found", systemImage: "receipt", description: Text("Receipt and invoice emails appear here as mail downloads. You can also open any message and choose Save receipt."))
            }
            if metadata.contains(where: { $0.key.hasPrefix(accountID.map(ReceiptOverride.prefix) ?? "receipt-override:") && (try? ReceiptOverride.decode($0)) == nil }) {
                Text(ReceiptError.invalidData.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Receipts")
        .searchable(text: $query, prompt: "Merchant, subject or amount")
        .toolbar {
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
    private func receiptRow(_ receipt: ReceiptSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(receipt.merchant).font(.headline).lineLimit(1)
                    Spacer(minLength: 16)
                    Text(receipt.money?.display ?? "Amount unknown").font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.merchant).font(.headline)
                    Text(receipt.money?.display ?? "Amount unknown").font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
            Text(receipt.subject).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Text(receipt.kind + (receipt.reviewed ? " · Reviewed" : " · Detected"))
                Spacer()
                Text(receipt.receivedAt, format: .dateTime.day().month(.abbreviated))
            }.font(.caption).foregroundStyle(.secondary)
            if accountID == nil { Text(accounts.first { $0.id == receipt.accountID }?.email ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }.padding(.vertical, 8)
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
                Text(receipt.merchant).font(.title2.bold())
                Text(receipt.money?.display ?? "Amount unknown").font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                LabeledContent("Type", value: receipt.kind)
                LabeledContent("Received", value: receipt.receivedAt.formatted(date: .abbreviated, time: .shortened))
            } footer: { Text(receipt.reviewed ? "You reviewed these details in Dispatch." : "Detected from the email. Review against the original before using these details.") }
            Section("Source") {
                Text(receipt.subject)
                Text(receipt.senderEmail).font(.caption).foregroundStyle(.secondary)
                if let message { NavigationLink("Open original email") { GmailMessageView(message: message) } }
            }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Receipt").navigationBarTitleDisplayMode(.inline)
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
    @State private var errorMessage: String?
    init(context: ReceiptEditContext) {
        self.context = context
        let money = context.correction?.amountReviewed == true ? context.correction?.money : context.detected?.money
        _merchant = State(initialValue: context.correction?.merchant ?? context.detected?.merchant ?? ReceiptDetector.merchant(context.source))
        _amount = State(initialValue: money.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _currency = State(initialValue: money?.currency ?? "GBP")
        _included = State(initialValue: context.correction?.inclusion != "exclude")
    }
    var body: some View {
        Form {
            Section("Receipt details") {
                TextField("Merchant", text: $merchant).accessibilityIdentifier("receiptMerchant")
                TextField("Amount", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("receiptAmount")
                TextField("Currency", text: $currency).textInputAutocapitalization(.characters).autocorrectionDisabled()
                Toggle("Include in Receipts", isOn: $included)
            } footer: { Text("Leave the amount blank if it is unknown. Use a currency code such as GBP, EUR or USD. These changes stay on this device.") }
            Section("Original email") {
                Text(context.source.subject)
                Text(context.source.senderEmail).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Review receipt").navigationBarTitleDisplayMode(.inline)
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
             receipt.money?.currency ?? "", receipt.subject, receipt.senderEmail, receipt.reviewed ? "Reviewed" : "Detected"].map(cell).joined(separator: ",")
        }
        return (["Date,Account,Merchant,Type,Amount,Currency,Subject,Sender,Status"] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
