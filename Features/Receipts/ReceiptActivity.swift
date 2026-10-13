import Foundation

enum ReceiptActivity {
    struct Month: Identifiable, Equatable {
        let date: Date
        var incoming = Decimal.zero
        var outgoing = Decimal.zero
        var id: Date { date }
    }
    static func months(_ receipts: [ReceiptSummary], currency: String, now: Date = Date(), calendar: Calendar = .current) -> [Month] {
        let end = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let buckets = (-5...0).compactMap { calendar.date(byAdding: .month, value: $0, to: end) }
        return buckets.map { date in
            var month = Month(date: date)
            for receipt in receipts where calendar.isDate(receipt.receivedAt, equalTo: date, toGranularity: .month) {
                guard let money = receipt.money, money.currency == currency else { continue }
                switch receipt.flow {
                case .incoming: month.incoming += money.amount
                case .outgoing: month.outgoing += money.amount
                case .unknown: break
                }
            }
            return month
        }
    }
}
