import SwiftUI

struct InlineMailSummary: View {
    let sources: [MailSummarySource]
    var loadingBody = false
    var securitySymbol: String = "shield"
    var securityColor: Color = .secondary
    var securityLabel = "Security Inspector, analysis incomplete"
    var securityIdentifier = "summarySecurityInspector"
    var onSecurity: (() -> Void)? = nil
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var result: MailSummaryResult?
    @State private var expanded = false
    @State private var running = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    @State private var requestID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let onSecurity {
                    Button(action: onSecurity) {
                        Image(systemName: securitySymbol).font(.system(size: 19)).foregroundStyle(securityColor).frame(width: 44, height: 44).contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityLabel(securityLabel).accessibilityIdentifier(securityIdentifier)
                }
                Button(running ? "Summarising…" : expanded ? "Hide summary" : "Summarise") {
                    if result != nil { withAnimation(MailStyle.motion(reduced: reduceMotion)) { expanded.toggle() }; return }
                    running = true; error = nil
                    let id = UUID(); requestID = id
                    job = Task {
                        defer { if requestID == id { running = false } }
                        do {
                            let value = try await runtime.localModel.summarise(sources)
                            guard !Task.isCancelled, requestID == id else { return }
                            withAnimation(MailStyle.motion(reduced: reduceMotion)) { result = value; expanded = true }
                        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                    }
                }.buttonStyle(.plain).font(.subheadline.weight(.medium)).foregroundStyle(MailStyle.accent).frame(minHeight: 44)
                    .disabled(loadingBody || (runtime.localModel.busy && !running) || running)
                    .accessibilityIdentifier("inlineSummaryButton")
                if running { Button("Cancel") { job?.cancel() }.font(.caption) }
                Spacer(minLength: 0)
            }
            if expanded, let result {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if result.generated { Text("Review details in the message.").font(.caption).foregroundStyle(.secondary) }
                    if result.missingBodies > 0 { Text("\(result.missingBodies) messages have no downloaded text body.").font(.caption).foregroundStyle(.secondary) }
                }.padding(.leading, 12)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(MailStyle.accent.opacity(0.25)).frame(width: 2) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if error != nil && !runtime.localModel.canWrite {
                NavigationLink("Set up on-device AI") { MailIntegrationSettings() }.font(.subheadline)
            }
        }
        .onChange(of: sources) { _, _ in job?.cancel(); requestID = UUID(); running = false; result = nil; expanded = false; error = nil }
        .onDisappear { job?.cancel() }
    }
}
