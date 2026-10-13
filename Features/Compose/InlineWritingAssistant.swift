import SwiftUI

struct InlineWritingAssistant: View {
    let source: String
    let draftUnchanged: Bool
    let apply: (String) -> Void
    let reviewInDraft: (String) -> Void
    let close: () -> Void
    @Environment(AppRuntime.self) private var runtime
    @State private var task: LocalWritingTask?
    @State private var revision = ""
    @State private var error: String?
    @State private var running = false
    @State private var request = 0
    @State private var requestID = UUID()
    private let tasks: [LocalWritingTask] = [.shorten, .expand, .proofread, .polish, .professional, .friendly]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Writing assistance", systemImage: "sparkles").font(.headline).foregroundStyle(MailStyle.intelligence)
                    Spacer()
                    MailCloseButton(title: "Close writing assistance", action: close).accessibilityIdentifier("writingDoneButton")
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
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(tasks) { option in
                        Button {
                            task = option; revision = ""; request += 1
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: symbol(option)).font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(color(option)).frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(MailStyle.ink)
                                    Text(hint(option)).font(.caption).foregroundStyle(MailStyle.secondaryInk)
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, minHeight: 64)
                                .background(task == option ? color(option).opacity(0.14) : MailStyle.tile, in: .rect(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(task == option ? color(option) : .clear, lineWidth: 1.5) }
                        }.buttonStyle(.plain).disabled(running || !runtime.localModel.canWrite || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityAddTraits(task == option ? [.isSelected] : [])
                    }
                }
                if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write a draft or select a passage to get started.").font(.callout).foregroundStyle(.secondary)
                } else if running {
                    HStack { ProgressView(); Text("Preparing your revision…").font(.callout).foregroundStyle(.secondary) }
                } else if task == nil {
                    Text("Choose what you want to change. You’ll review every edit before applying it.").font(.callout).foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                    Button("Try again") { request += 1 }.disabled(running)
                }
                if !revision.isEmpty {
                    if revision == source { Text("No changes needed.").font(.callout).foregroundStyle(.secondary) }
                    MailRule()
                    HStack {
                        Text("\(MailWritingRevision.wordCount(source)) → \(MailWritingRevision.wordCount(revision)) words").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("Added").foregroundStyle(.green)
                        Text("Removed").foregroundStyle(.red).strikethrough()
                    }.font(.caption)
                    Text(LocalWritingView.comparison(original: source, revised: revision))
                        .font(.body).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        .accessibilityIdentifier("writingSuggestion")
                    if !draftUnchanged {
                        Text("Your draft changed. Close and reopen writing assistance to use the latest text.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Review changes in the draft", systemImage: "doc.text.magnifyingglass") { reviewInDraft(revision) }
                        .disabled(!draftUnchanged).font(.subheadline).accessibilityIdentifier("previewWritingInDraft")
                    HStack {
                        Button("Apply changes") { apply(revision) }.buttonStyle(.borderedProminent).tint(MailStyle.intelligence)
                            .disabled(!draftUnchanged || running || revision == source).accessibilityIdentifier("acceptWritingSuggestion")
                        Spacer()
                        Button("Try another") { request += 1 }.disabled(running)
                    }
                }
            }.padding(20)
        }.background(MailStyle.paper).accessibilityIdentifier("inlineWritingAssistant")
            .task(id: "\(task?.id ?? "choose")-\(request)-\(runtime.localModel.canWrite)") {
                guard let task, runtime.localModel.canWrite, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let id = UUID(); requestID = id; running = true; error = nil; revision = ""
                defer { if requestID == id { running = false } }
                do {
                    let value = try await runtime.localModel.generate(task, text: source)
                    guard !Task.isCancelled, requestID == id else { return }
                    revision = value
                } catch { if !Task.isCancelled && requestID == id { self.error = error.localizedDescription } }
            }
    }
    private func symbol(_ option: LocalWritingTask) -> String {
        switch option {
        case .shorten: "arrow.down.right.and.arrow.up.left"
        case .expand: "arrow.up.left.and.arrow.down.right"
        case .proofread: "checkmark.circle"
        case .professional: "briefcase"
        case .friendly: "face.smiling"
        default: "wand.and.stars"
        }
    }
    private func color(_ option: LocalWritingTask) -> Color {
        switch option {
        case .shorten: .orange
        case .expand: .teal
        case .proofread: .blue
        case .professional: MailStyle.accent
        case .friendly: MailStyle.success
        default: MailStyle.intelligence
        }
    }
    private func hint(_ option: LocalWritingTask) -> String {
        switch option {
        case .shorten: "Keep the essentials"
        case .expand: "Develop your points"
        case .proofread: "Fix mistakes only"
        case .professional: "Clear and courteous"
        case .friendly: "Warm and natural"
        default: "Improve the flow"
        }
    }
}
