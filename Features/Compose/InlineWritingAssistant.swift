import SwiftUI

struct InlineWritingAssistant: View {
    let source: String
    let draftUnchanged: Bool
    let reviewInDraft: (String) -> Void
    let setup: () -> Void
    let close: () -> Void
    @Environment(AppRuntime.self) private var runtime
    @Environment(MailFeedback.self) private var feedback
    @State private var task: LocalWritingTask?
    @State private var running = false
    @State private var request = 0
    private let tasks: [LocalWritingTask] = [.shorten, .expand, .proofread, .polish, .professional, .friendly]

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tasks) { option in
                        Button {
                            guard runtime.localModel.canWrite else { return }
                            task = option; request += 1
                        } label: {
                            HStack(spacing: 7) {
                                if running && task == option { ProgressView().controlSize(.small) }
                                else { Image(systemName: symbol(option)).font(.system(size: 17, weight: .medium)) }

                            }.foregroundStyle(MailIntelligenceStyle.gradient).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(option.rawValue)
                            .accessibilityIdentifier("writingTool-\(option.id)")
                            .disabled(running || !runtime.localModel.canWrite || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            if !runtime.localModel.canWrite {
                Button(action: setup) { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Set up writing assistance")
            }
            MailCloseButton(title: running ? "Cancel writing assistance" : "Close writing assistance", action: close)
                .accessibilityIdentifier("writingDoneButton").padding(.trailing, 8)
        }.frame(height: 52).padding(.horizontal, 8).modifier(MailIntelligenceSurface(running: running))
            .accessibilityElement(children: .contain).accessibilityIdentifier("inlineWritingAssistant")
            .task(id: "\(task?.id ?? "choose")-\(request)") {
                guard let task, runtime.localModel.canWrite else { return }
                running = true
                defer { running = false }
                do {
                    let value = try await runtime.localModel.generate(task, text: source)
                    guard !Task.isCancelled else { return }
                    guard draftUnchanged else {
                        close(); feedback.show("Draft changed", detail: "Reopen writing assistance to use the latest text.", tone: .information); return
                    }
                    reviewInDraft(value)
                } catch {
                    guard !Task.isCancelled else { return }
                    close(); feedback.show("Couldn’t revise draft", detail: error.localizedDescription, tone: .error)
                }
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
}
