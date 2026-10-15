import SwiftUI

struct MailFloatingActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 56, height: 56, alignment: .center)
                .foregroundStyle(MailStyle.paper)
                .background(MailStyle.accent, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Keep glass on controls, with a full native touch target and a spoken label.
struct MailGlassButton: View {
    let title: String
    let symbol: String
    var tint: Color? = nil
    let action: () -> Void
    @Environment(MailFeedback.self) private var feedback
    var body: some View {
        Button { feedback.select(); action() } label: {
            Image(systemName: symbol).font(MailStyle.icon)
                .frame(width: 44, height: 44).contentShape(.circle)
        }
        .buttonStyle(.plain).modifier(MailControlSurface())
        .foregroundStyle(tint ?? MailStyle.ink)
        .accessibilityLabel(title)
    }
}
