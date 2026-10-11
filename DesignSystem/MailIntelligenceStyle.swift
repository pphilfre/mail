import SwiftUI

enum MailIntelligenceStyle {
    static let gradient = LinearGradient(colors: [.blue, .purple, .pink, .orange], startPoint: .leading, endPoint: .trailing)
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
            }.foregroundStyle(MailIntelligenceStyle.gradient)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Color.secondary.opacity(0.06), in: .capsule)
                .overlay { Capsule().strokeBorder(MailIntelligenceStyle.gradient.opacity(running ? 0.8 : 0.35), lineWidth: 1) }
                .shadow(color: .purple.opacity(running ? 0.18 : 0), radius: 8)
        }.buttonStyle(.plain)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: running)
    }
}
