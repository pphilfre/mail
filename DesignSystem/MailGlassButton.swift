import SwiftUI

struct MailReaderActionSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.foregroundStyle(MailStyle.ink).tint(MailStyle.ink).background(MailStyle.tile, in: .capsule)
        } else {
            content.foregroundStyle(MailStyle.ink).tint(MailStyle.ink)
                .glassEffect(.regular.tint(MailStyle.tile).interactive(), in: .capsule)
        }
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
