import SwiftUI

enum MailSecurityStatus: Equatable {
    case unknown, lowRisk, uncertain, suspicious
    init(report: SecurityReport?) {
        guard let report else { self = .unknown; return }
        if report.verdict == .concern { self = report.score >= 40 ? .suspicious : .uncertain }
        else { self = report.verdict == .checked ? .lowRisk : .unknown }
    }
    var color: Color {
        switch self { case .unknown: .secondary; case .lowRisk: .green; case .uncertain: .orange; case .suspicious: .red }
    }
    var symbol: String {
        switch self { case .unknown: "questionmark.shield"; case .lowRisk: "checkmark.shield"; case .uncertain: "exclamationmark.shield"; case .suspicious: "xmark.shield" }
    }
    var label: String {
        switch self { case .unknown: "Analysis incomplete"; case .lowRisk: "Low observed risk"; case .uncertain: "Review concerns"; case .suspicious: "Suspicious" }
    }
}
