import SwiftUI

enum MailIntelligenceStyle {
    static let foreground = MailStyle.intelligence
    static let gradient = LinearGradient(colors: [Color(red: 0.35, green: 0.58, blue: 0.96), Color(red: 0.67, green: 0.52, blue: 0.88)], startPoint: .leading, endPoint: .trailing)
}

/// Motion is limited to work in progress; idle controls do not keep the render loop alive.
struct MailIntelligenceSurface: ViewModifier {
    var running = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flowing = false
    func body(content: Content) -> some View {
        content
            .modifier(MailControlSurface())
            .overlay {
                Capsule().strokeBorder(MailIntelligenceStyle.gradient, lineWidth: 1.5)
                    .opacity(flowing ? 0.5 : 0.85)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .onChange(of: running, initial: true) { _, active in
                withAnimation(active && !reduceMotion ? .linear(duration: 2).repeatForever(autoreverses: true) : nil) {
                    flowing = active && !reduceMotion
                }
            }
            .onChange(of: reduceMotion) { _, _ in flowing = false }
    }
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
                .modifier(MailIntelligenceSurface(running: running))
        }.buttonStyle(.plain)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: running)
    }
}
