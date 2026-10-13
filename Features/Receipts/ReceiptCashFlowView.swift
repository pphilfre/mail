import SwiftUI
import Charts

extension ReceiptFlow {
    var color: Color { self == .incoming ? MailStyle.success : self == .outgoing ? .red : MailStyle.secondaryInk }
}

struct ReceiptCashFlowView: View {
    let receipts: [ReceiptSummary]
    @State private var selectedCurrency = ""
    private var currencies: [String] { Array(Set(receipts.compactMap { $0.money?.currency })).sorted() }
    private var currency: String { currencies.contains(selectedCurrency) ? selectedCurrency : currencies.first ?? "GBP" }
    var body: some View {
        let months = ReceiptActivity.months(receipts, currency: currency)
        let incoming = months.reduce(Decimal.zero) { $0 + $1.incoming }
        let outgoing = months.reduce(Decimal.zero) { $0 + $1.outgoing }
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Cash flow").font(.headline)
                Spacer()
                if currencies.count > 1 {
                    Picker("Currency", selection: Binding(get: { currency }, set: { selectedCurrency = $0 })) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                } else { Text(currency).font(.subheadline).foregroundStyle(.secondary) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { total("Money in", incoming, color: MailStyle.success); total("Money out", outgoing, color: .red) }
                VStack(alignment: .leading, spacing: 12) { total("Money in", incoming, color: MailStyle.success); total("Money out", outgoing, color: .red) }
            }
            if incoming > 0 || outgoing > 0 {
                Chart {
                  ForEach(months) { month in
                    BarMark(x: .value("Month", month.date, unit: .month), y: .value("Money in", NSDecimalNumber(decimal: month.incoming).doubleValue))
                        .foregroundStyle(MailStyle.success)
                    BarMark(x: .value("Month", month.date, unit: .month), y: .value("Money out", -NSDecimalNumber(decimal: month.outgoing).doubleValue))
                        .foregroundStyle(.red)
                  }
                  RuleMark(y: .value("Zero", 0)).foregroundStyle(MailStyle.divider)
                }.chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 150).accessibilityLabel("Six-month cash flow in " + currency + ". Green is incoming, red is outgoing.")
            } else {
                Text("Confirmed amounts will appear here.").font(.callout).foregroundStyle(MailStyle.secondaryInk)
            }
        }.padding(.vertical, 8).accessibilityElement(children: .contain).accessibilityIdentifier("receiptCashFlow")
    }
    private func total(_ title: String, _ value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(MailStyle.secondaryInk)
            Text(ReceiptMoney(amount: value, currency: currency).display).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }.fixedSize(horizontal: true, vertical: false)
    }
}
