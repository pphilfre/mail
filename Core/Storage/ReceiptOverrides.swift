import Foundation
import SwiftData

struct ReceiptOverride: Codable, Equatable, Sendable {
    var version = 1
    let accountID: UUID
    let remoteID: String
    var inclusion = "include"
    var merchant: String?
    var money: ReceiptMoney?
    var amountReviewed = false
    static func prefix(_ id: UUID) -> String { "receipt-override:\(id.uuidString):" }
    var key: String { Self.prefix(accountID) + remoteID }
    static func decode(_ row: StoreMetadata) throws -> ReceiptOverride {
        let value = try JSONDecoder().decode(Self.self, from: Data(row.value.utf8))
        guard value.version == 1, value.key == row.key, ["include", "exclude"].contains(value.inclusion) else { throw ReceiptError.invalidData }
        return value
    }
    func apply(to source: ReceiptSource, detected: ReceiptSummary?) -> ReceiptSummary? {
        guard inclusion != "exclude" else { return nil }
        var result = detected ?? ReceiptSummary(id: source.id, accountID: source.accountID, remoteID: source.remoteID,
            merchant: ReceiptDetector.merchant(source), kind: "Receipt", money: nil, subject: source.subject,
            senderEmail: source.senderEmail, receivedAt: source.receivedAt)
        if let merchant { result.merchant = merchant }
        if amountReviewed { result.money = money }
        result.reviewed = true
        return result
    }
}

enum ReceiptError: LocalizedError {
    case invalidData, invalidAmount
    var errorDescription: String? {
        switch self {
        case .invalidData: "A saved receipt correction could not be read. Its saved data has been kept."
        case .invalidAmount: "Enter a valid amount and a three-letter currency such as GBP, EUR or USD. Leave the amount blank if it is unknown."
        }
    }
}

@MainActor extension MailRepository {
    func saveReceipt(_ correction: ReceiptOverride) throws {
        guard try account(id: correction.accountID) != nil else { throw GmailError.reconnect }
        guard correction.version == 1, ["include", "exclude"].contains(correction.inclusion) else { throw ReceiptError.invalidData }
        if let money = correction.money {
            guard money.amount >= 0, money.currency.range(of: #"^(?:[A-Z]{3}|[$¥])$"#, options: .regularExpression) != nil else { throw ReceiptError.invalidAmount }
        }
        try context.transaction {
            try setMetadata(correction.key, value: String(decoding: try JSONEncoder().encode(correction), as: UTF8.self))
            try context.save()
        }
    }
}
