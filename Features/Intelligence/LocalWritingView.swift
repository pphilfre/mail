import SwiftUI

struct LocalWritingView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let tasks: [LocalWritingTask]
    var apply: ((String) -> Void)?
    @State private var selected: LocalWritingTask
    @State private var output = ""
    @State private var error: String?
    @State private var running = false
    @State private var showingOriginal = false
    @State private var request = 0
    init(text: String, tasks: [LocalWritingTask], apply: ((String) -> Void)? = nil) {
        self.text = text; self.tasks = tasks; self.apply = apply
        _selected = State(initialValue: tasks.first ?? .polish)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if tasks.count > 1 {
                    Picker("Writing tool", selection: $selected) { ForEach(tasks) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.menu).disabled(running)
                }
                if !runtime.localModel.canWrite {
                    Label("Enable Apple Intelligence or download the writing model in Privacy & Intelligence.", systemImage: "arrow.down.circle")
                        .font(.callout).foregroundStyle(.secondary)
                    NavigationLink { MailIntegrationSettings() } label: { Label("Set up writing tools", systemImage: "sparkles") }
                        .accessibilityIdentifier("writingSetupButton")
                } else if running {
                    HStack { ProgressView(); Text("Polishing on this device…").foregroundStyle(.secondary) }
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                    IntelligenceAction(title: "Try again") { request += 1 }
                }
                if !output.isEmpty {
                    Picker("Compare writing", selection: $showingOriginal) {
                        Text("Original").tag(true); Text("Revised").tag(false)
                    }.pickerStyle(.segmented)
                    Text(showingOriginal ? AttributedString(text) : Self.comparison(original: text, revised: output))
                        .font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .id(showingOriginal)
                        .transition(.opacity)
                    Text("Green words are added. Red struck-through words are removed.").font(.caption).foregroundStyle(.secondary)
                    if let apply {
                        Button("Use revision", systemImage: "checkmark") { apply(output); dismiss() }
                            .buttonStyle(.glassProminent).disabled(output == text)
                    }
                } else if !running { Text(text).textSelection(.enabled) }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(MailStyle.paper)
        .navigationTitle("Polish writing").navigationBarTitleDisplayMode(.inline)
        .animation(MailStyle.motion(reduced: reduceMotion), value: showingOriginal)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.accessibilityIdentifier("writingDoneButton")
        } }
        .task(id: "\(selected.id)-\(request)-\(runtime.localModel.canWrite)") {
            guard runtime.localModel.canWrite, !text.isEmpty else { return }
            running = true; error = nil; output = ""
            defer { running = false }
            do {
                let value = try await runtime.localModel.generate(selected, text: text)
                guard !Task.isCancelled else { return }
                withAnimation(MailStyle.motion(reduced: reduceMotion)) { output = value }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    static func comparison(original: String, revised: String) -> AttributedString {
        var result = AttributedString()
        for run in MailWritingRevision.runs(original: original, revised: revised) {
            var value = AttributedString(run.text)
            if run.change == .added { value.foregroundColor = .green; value.backgroundColor = .green.opacity(0.1) }
            if run.change == .removed { value.foregroundColor = .red; value.strikethroughStyle = .single }
            result += value
        }
        return result
    }
}
