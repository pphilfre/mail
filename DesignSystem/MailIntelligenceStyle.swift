import SwiftUI

enum MailIntelligenceStyle {
    static let foreground = MailStyle.intelligence
}

struct IntelligenceAction: View {
    let title: String
    var running = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if running { ProgressView().controlSize(.small) }
                else { Image(systemName: "sparkles") }
                Text(title).font(.subheadline.weight(.semibold))
            }.foregroundStyle(MailIntelligenceStyle.foreground)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(MailStyle.tile, in: .rect(cornerRadius: MailStyle.controlRadius))
        }.buttonStyle(.plain)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: running)
    }
}
