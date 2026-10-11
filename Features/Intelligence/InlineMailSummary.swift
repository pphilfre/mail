import SwiftUI

struct InlineMailSummary: View {
    let sources: [MailSummarySource]
    var loadingBody = false
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var result: MailSummaryResult?
    @State private var expanded = false
    @State private var running = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IntelligenceAction(title: running ? "Summarising…" : expanded ? "Hide summary" : "Summarise", running: running) {
                    if result != nil { withAnimation(MailStyle.motion(reduced: reduceMotion)) { expanded.toggle() }; return }
                    running = true; error = nil
                    job = Task {
                        defer { running = false }
                        do {
                            let value = try await runtime.localModel.summarise(sources)
                            guard !Task.isCancelled else { return }
                            withAnimation(MailStyle.motion(reduced: reduceMotion)) { result = value; expanded = true }
                        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                    }
                }.disabled(loadingBody || (runtime.localModel.busy && !running) || running)
                    .accessibilityIdentifier("inlineSummaryButton")
                if running { Button("Cancel") { job?.cancel() }.font(.caption) }
            }
            if expanded, let result {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.generated ? "Summary · on this device" : "Key passages · from message bodies")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(result.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if result.generated { Text("Review details in the message.").font(.caption).foregroundStyle(.secondary) }
                }.padding(.leading, 12)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(MailIntelligenceStyle.gradient).frame(width: 3) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .onChange(of: sources) { _, _ in job?.cancel(); result = nil; expanded = false; error = nil }
        .onDisappear { job?.cancel() }
    }
}
