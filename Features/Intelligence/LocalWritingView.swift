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
                    NavigationLink("Set up writing tools", systemImage: "sparkles") { MailIntegrationSettings() }
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
                    Text("Coloured words changed. Review before replacing your draft.").font(.caption).foregroundStyle(.secondary)
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
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
        // Word diff identifies additions/replacements rather than colouring every word present elsewhere.
        let old = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let next = revised.split(whereSeparator: \.isWhitespace).map(String.init)
        let additions = Set(next.difference(from: old).compactMap { change -> Int? in
            if case .insert(let offset, _, _) = change { return offset }; return nil
        })
        var result = AttributedString()
        var cursor = revised.startIndex
        for (index, word) in next.enumerated() {
            guard let range = revised.range(of: word, range: cursor..<revised.endIndex) else { continue }
            result += AttributedString(String(revised[cursor..<range.lowerBound]))
            var value = AttributedString(String(revised[range]))
            if additions.contains(index) { value.foregroundColor = .purple; value.backgroundColor = .purple.opacity(0.08) }
            result += value; cursor = range.upperBound
        }
        result += AttributedString(String(revised[cursor...]))
        return result
    }
}
