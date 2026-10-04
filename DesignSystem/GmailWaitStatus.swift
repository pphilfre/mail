import SwiftUI

/// Only shown for a server-imposed cooldown; normal request pacing stays quiet.
struct GmailWaitStatus: View {
    let deadline: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
            HStack(spacing: 6) {
                Image(systemName: remaining > 0 ? "clock" : "arrow.clockwise")
                Text(remaining > 0 ? "Waiting for Gmail" : "Updating mail…")
                if remaining > 0 {
                    Text("\(remaining)s").monospacedDigit()
                        .accessibilityLabel("Retrying in \(remaining) seconds")
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
