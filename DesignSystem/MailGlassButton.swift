import SwiftUI

/// Keep glass on controls, with a full native touch target and a spoken label.
struct MailGlassButton: View {
    let title: String
    let symbol: String
    var tint: Color? = nil
    let action: () -> Void
    @Environment(MailFeedback.self) private var feedback
    var body: some View {
        Button { feedback.select(); action() } label: {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: 44).contentShape(.circle)
        }
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .foregroundStyle(tint ?? .primary)
        .accessibilityLabel(title)
    }
}
