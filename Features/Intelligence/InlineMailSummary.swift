import SwiftUI

struct InlineMailSummary: View {
    let sources: [MailSummarySource]
    var loadingBody = false
    var securitySymbol: String = "shield"
    var securityColor: Color = .secondary
    var securityLabel = "Security Inspector, analysis incomplete"
    var securityIdentifier = "summarySecurityInspector"
    var securityLoading = false
    var onSecurity: (() -> Void)? = nil
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var result: MailSummaryResult?
    @State private var expanded = false
    @State private var running = false
    @State private var requested = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    @State private var requestID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let onSecurity {
                    Button(action: onSecurity) {
                        Image(systemName: securityLoading ? "shield" : securitySymbol).font(MailStyle.icon)
                            .foregroundStyle(securityColor).frame(width: 44, height: 44)
                            .overlay(alignment: .bottomTrailing) {
                                if securityLoading { ProgressView().controlSize(.mini).padding(3) }
                            }.contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityLabel(securityLoading ? "Security Inspector, checking downloaded content" : securityLabel).accessibilityIdentifier(securityIdentifier)
                }
                Button {
                    requested = true
                    if result != nil { withAnimation(MailStyle.motion(reduced: reduceMotion)) { expanded.toggle() }; return }
                    if !running && !loadingBody { prepareSummary() }
                } label: {
                    HStack(spacing: 6) {
                        if (running || loadingBody) && requested { ProgressView().controlSize(.small) }
                        else { Image(systemName: "text.alignleft").foregroundStyle(MailStyle.ink) }
                        Text(loadingBody && requested ? "Loading message…" : running && requested ? "Summarising…" : "Summarise")
                            .foregroundStyle(MailIntelligenceStyle.gradient)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(MailStyle.ink)
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).contentShape(.rect)
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("inlineSummaryButton")
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                if running && requested { MailCloseButton(title: "Cancel summary") { job?.cancel(); running = false; requested = false } }
                Spacer(minLength: 0)
            }
            if expanded, let result {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if result.missingBodies > 0 { Text("\(result.missingBodies) messages have no downloaded text body.").font(.caption).foregroundStyle(.secondary) }
                }.padding(.leading, 12)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(MailStyle.accent.opacity(0.25)).frame(width: 2) }
                    .transition(.opacity)
            }
            if requested, let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if requested && error != nil && !runtime.localModel.canWrite {
                NavigationLink("Set up on-device AI") { MailIntegrationSettings() }.font(.subheadline)
            }
        }
        .task(id: sources) {
            job?.cancel(); requestID = UUID(); running = false; result = nil; expanded = false; error = nil
            let saved = await MailSummaryCache.shared.value(for: sources)
            guard !Task.isCancelled, !running else { return }
            result = saved
            if saved == nil && !loadingBody { prepareSummary() }
            else if saved != nil && requested { expanded = true }
        }
        .onChange(of: loadingBody) { _, loading in
            if !loading && result == nil && !running { prepareSummary() }
        }
        .onDisappear { job?.cancel() }
    }

    private func prepareSummary() {
        guard !running else { return }
        running = true; error = nil
        let id = UUID(); requestID = id
        let snapshot = sources
        job = Task {
            defer { if requestID == id { running = false } }
            do {
                let cached = await MailSummaryCache.shared.value(for: snapshot)
                let value: MailSummaryResult
                if let cached { value = cached }
                else {
                    value = try await runtime.localModel.summarise(snapshot)
                    try Task.checkCancellation()
                    await MailSummaryCache.shared.store(value, for: snapshot)
                }
                guard !Task.isCancelled, requestID == id else { return }
                result = value
                if requested { withAnimation(MailStyle.motion(reduced: reduceMotion)) { expanded = true } }
            } catch { if !Task.isCancelled && requestID == id { self.error = error.localizedDescription } }
        }
    }
}
