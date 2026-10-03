import SwiftUI

/// Website icons are decorative; they are never evidence of sender verification.
struct SenderAvatar: View {
    let email: String
    let name: String
    @AppStorage("senderPictures") private var senderPictures = true
    private var iconURL: URL? {
        guard senderPictures, let domain = email.split(separator: "@").last?.lowercased(),
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
        Text(initials).font(.system(size: 15, weight: .semibold)).foregroundStyle(MailStyle.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MailStyle.accent.opacity(0.1))
    }
    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { image in
                    image.resizable().scaledToFit().padding(9).background(.background)
                } placeholder: { fallback }
            } else { fallback }
        }
        .frame(width: 42, height: 42)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}
