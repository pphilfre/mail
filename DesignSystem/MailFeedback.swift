import SwiftUI
import Observation
import UIKit

@MainActor
@Observable
final class MailFeedback {
    enum Tone: Equatable { case success, error, information }
    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let detail: String?
        let symbol: String
        let tone: Tone
        let undo: (() -> Void)?
        let expiresAt: Date?
    }

    var confirmation: Confirmation?
    var selection = 0
    var triageKind: String?

    func select() { selection += 1 }

    func show(_ title: String, detail: String? = nil, symbol: String = "checkmark", tone: Tone = .success,
              expiresAt: Date? = nil, undo: (() -> Void)? = nil) {
        confirmation = Confirmation(title: title, detail: detail, symbol: symbol, tone: tone, undo: undo, expiresAt: expiresAt)
        UIAccessibility.post(notification: .announcement, argument: title)
    }

    func confirmTriage(_ record: MailUndoRecord, online: Bool, undo: @escaping () -> Void) {
        let subject = record.count == 1 ? "Message" : "\(record.count) messages"
        let title: String
        switch record.title {
        case "archive": title = "\(subject) archived"
        case "trash": title = "\(subject) moved to Trash"
        case "restore": title = "\(subject) restored"
        case "read": title = "Marked as read"
        case "unread": title = "Marked as unread"
        case "star": title = "\(subject) starred"
        case "unstar": title = "Star removed"
        case "spam": title = "Moved to Spam"
        case "notSpam": title = "Moved out of Spam"
        default: title = "Labels updated"
        }
        show(title, detail: online ? "Saved on this device" : "Will sync when you’re online",
             symbol: record.title == "archive" ? "archivebox" : "checkmark", expiresAt: record.expiresAt, undo: undo)
    }
}

struct MailFeedbackOverlay: ViewModifier {
    var playsHaptics = true
    @Environment(MailFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hapticFeedback") private var haptics = true
    @AppStorage("confirmationAnimations") private var animations = true

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let confirmation = feedback.confirmation {
                    ConfirmationToast(confirmation: confirmation, animated: animations && !reduceMotion) {
                        feedback.confirmation = nil
                    }
                    .id(confirmation.id)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 88)
                    .transition(reduceMotion || !animations ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: confirmation.id) {
                        let duration = confirmation.undo == nil ? 3.0 :
                            (confirmation.expiresAt?.timeIntervalSinceNow ?? 10.0)
                        do { try await Task.sleep(for: .seconds(max(0, duration))) }
                        catch { return }
                        guard feedback.confirmation?.id == confirmation.id else { return }
                        feedback.confirmation = nil
                    }
                }
            }
            .animation(animations ? MailStyle.motion(reduced: reduceMotion) : nil, value: feedback.confirmation?.id)
            .sensoryFeedback(.selection, trigger: feedback.selection) { _, _ in haptics && playsHaptics }
            .sensoryFeedback(trigger: feedback.confirmation?.id) { _, newID in
                guard haptics, playsHaptics, newID != nil else { return nil }
                switch feedback.confirmation?.tone {
                case .some(.success): return .success
                case .some(.error): return .error
                default: return .selection
                }
            }
    }
}

private struct ConfirmationToast: View {
    let confirmation: MailFeedback.Confirmation
    let animated: Bool
    let close: () -> Void
    @State private var arrived = false
    private var color: Color { confirmation.tone == .success ? MailStyle.success : confirmation.tone == .error ? .red : MailStyle.accent }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: confirmation.symbol)
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                    .scaleEffect(arrived ? 1 : 0.45)
                    .rotationEffect(.degrees(arrived ? 0 : -20))
                if confirmation.tone == .success && animated {
                    ForEach(0..<5) { index in
                        Circle().fill(color).frame(width: 3, height: 3)
                            .offset(y: arrived ? -27 : -12)
                            .rotationEffect(.degrees(Double(index) * 72))
                            .opacity(arrived ? 0 : 1)
                    }
                }
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(confirmation.title).font(.subheadline.weight(.semibold)).accessibilityIdentifier("mailConfirmationTitle")
                if let detail = confirmation.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
            if let undo = confirmation.undo {
                Button { close(); undo() } label: {
                    Text("Undo").font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }.buttonStyle(.plain).foregroundStyle(MailStyle.accent).accessibilityIdentifier("triageUndo")
            } else {
                Button(action: close) {
                    Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 44, height: 44)
                }.accessibilityLabel("Dismiss confirmation")
            }
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 8)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .task {
            withAnimation(animated ? .spring(duration: 0.42, bounce: 0.32) : nil) { arrived = true }
        }
    }
}
