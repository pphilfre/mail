import SwiftUI

enum MailStyle {
    static let accent = Color(red: 0.15, green: 0.40, blue: 0.92)
    static let success = Color(red: 0.16, green: 0.62, blue: 0.43)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let paper = Color(uiColor: .secondarySystemGroupedBackground)
    static let rowSpacing: CGFloat = 5
    static let contentPadding: CGFloat = 20

    static func motion(reduced: Bool) -> Animation? {
        reduced ? nil : .snappy(duration: 0.22, extraBounce: 0.06)
    }

    static func mailboxSymbol(_ name: String) -> String {
        switch name {
        case "Inbox": "tray"
        case "All Mail": "tray.2"
        case "Unread": "envelope.badge"
        case "Starred": "star"
        case "Sent": "paperplane"
        case "Drafts": "square.and.pencil"
        case "Archive": "archivebox"
        case "Spam": "exclamationmark.shield"
        default: "trash"
        }
    }

    static func accountTitle(_ account: MailAccount, unread: Int) -> String {
        account.displayName + (unread > 0 ? " (\(unread) unread)" : "")
    }
}

/// A shared minimum touch target for compact, icon-only navigation controls.
struct MailCloseButton: View {
    @Environment(MailFeedback.self) private var feedback
    var title = "Close"
    let action: () -> Void

    var body: some View {
        Button { feedback.select(); action() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel(title)
    }
}
