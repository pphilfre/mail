import SwiftUI

/// Website icons are decorative; they are never evidence of sender verification.
struct SenderAvatar: View {
    let email: String
    let name: String
    var allowsRemoteIcon = true
    @AppStorage("senderPictures") private var senderPictures = true
    private var iconURL: URL? {
        guard allowsRemoteIcon, senderPictures, let domain = email.split(separator: "@").last?.lowercased(),
              domain.contains("."), domain.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              !["gmail.com", "outlook.com", "hotmail.com", "icloud.com", "yahoo.com", "live.com", "aol.com"].contains(domain)
        else { return nil }
        return URL(string: "https://\(domain)/favicon.ico")
    }
    private var initials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
    private var fallback: some View {
        Text(initials.isEmpty ? "?" : initials).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(avatarColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(avatarColor.opacity(0.08))
    }
    private var avatarColor: Color {
        let colors: [Color] = [MailStyle.accent, .teal, .purple, .indigo, .brown]
        let hash = email.utf8.reduce(0) { ($0 &+ Int($1)) % colors.count }
        return colors[hash]
    }
    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit().padding(9).background(.background) }
                    else { fallback }
                }
            } else { fallback }
        }
        .frame(width: 38, height: 38)
        .clipShape(.rect(cornerRadius: 13))
        .accessibilityHidden(true)
    }
}
