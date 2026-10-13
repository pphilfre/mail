import SwiftUI

struct InlineWritingAssistant: View {
    let source: String
    let draftUnchanged: Bool
    let apply: (String) -> Void
    let close: () -> Void
    @Environment(AppRuntime.self) private var runtime
    @State private var task = LocalWritingTask.polish
    @State private var revision = ""
    @State private var error: String?
    @State private var running = false
    @State private var request = 0
    @State private var requestID = UUID()
    private let tasks: [LocalWritingTask] = [.polish, .shorten, .expand, .proofread, .professional, .friendly]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Writing assistance").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
                    .frame(width: 44, height: 44).accessibilityIdentifier("writingDoneButton")
            }
            if let reason = runtime.localModel.unavailableReason {
                Text(reason).font(.callout).foregroundStyle(.secondary)
                if !runtime.localModel.installed && LocalModelWorker.supported {
                    Button("Download model · 350 MB over Wi-Fi") { Task { await runtime.localModel.download() } }
                        .disabled(runtime.localModel.busy).accessibilityIdentifier("writingSetupButton")
                }
                if let progress = runtime.localModel.downloadProgress {
                    ProgressView(value: progress)
                    Button("Cancel download") { runtime.localModel.cancel() }
                }
                if let status = runtime.localModel.status { Text(status).font(.caption).foregroundStyle(.secondary) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(tasks) { option in
                            Button(option.rawValue) { task = option; revision = ""; request += 1 }
                                .foregroundStyle(task == option ? MailStyle.accent : .secondary)
                                .frame(minHeight: 44).accessibilityAddTraits(task == option ? [.isSelected] : [])
                        }
                    }
                }.font(.subheadline).buttonStyle(.plain)
                if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write a draft or select a passage to get started.").font(.callout).foregroundStyle(.secondary)
                } else if running {
                    HStack { ProgressView(); Text("Preparing a suggestion on this device…").font(.callout).foregroundStyle(.secondary) }
                }
                if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
                if !revision.isEmpty {
                    ScrollView {
                        Text(LocalWritingView.comparison(original: source, revised: revision))
                            .font(.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.frame(maxHeight: 180).accessibilityIdentifier("writingSuggestion")
                    if !draftUnchanged {
                        Text("Your draft changed. Close and reopen writing assistance to use the latest text.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Accept") { apply(revision) }.disabled(!draftUnchanged || running)
                            .accessibilityIdentifier("acceptWritingSuggestion")
                        Button("Reject", action: close).foregroundStyle(.secondary)
                        Spacer()
                        Button("Regenerate") { request += 1 }.disabled(running)
                    }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                } else if error != nil {
                    Button("Try again") { request += 1 }.disabled(running)
                }
            }
        }.padding(12).background(MailStyle.tile, in: .rect(cornerRadius: 12))
            .accessibilityIdentifier("inlineWritingAssistant")
            .task(id: "\(task.id)-\(request)-\(runtime.localModel.canWrite)") {
                guard runtime.localModel.unavailableReason == nil, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let id = UUID(); requestID = id; running = true; error = nil; revision = ""
                defer { if requestID == id { running = false } }
                do {
                    let value = try await runtime.localModel.generate(task, text: source)
                    guard !Task.isCancelled, requestID == id else { return }
                    revision = value
                } catch { if !Task.isCancelled && requestID == id { self.error = error.localizedDescription } }
            }
    }
}
