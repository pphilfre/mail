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
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? .primary)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(title)
    }
}
