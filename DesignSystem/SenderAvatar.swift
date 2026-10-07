import SwiftUI
import ImageIO

/// Website icons are decorative; they are never evidence of sender verification.
struct SenderAvatar: View {
    let email: String
    let name: String
    var allowsRemoteIcon = true
    var size: CGFloat = 38
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
        Text(initials.isEmpty ? "?" : initials).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.primary)
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
                CompanyIcon(url: iconURL, size: size) { fallback }
            } else { fallback }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 13))
        .accessibilityHidden(true)
    }
}

private actor CompanyIconStore {
    static let shared = CompanyIconStore()
    private var cache: [URL: Data] = [:]
    private var requests: [URL: Task<Data?, Never>] = [:]
    private var misses: [URL: Date] = [:]
    private var bytes = 0
    func data(for url: URL) async -> Data? {
        if let data = cache[url] { return data }
        if let until = misses[url], until > Date() { return nil }
        if let request = requests[url] { return await request.value }
        let request = Task<Data?, Never> {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count <= 1_000_000 else { return nil }
            return data
        }
        requests[url] = request
        let result = await request.value
        requests[url] = nil
        if let result {
            if cache.count >= 100 || bytes + result.count > 8_000_000 { cache.removeAll(keepingCapacity: true); bytes = 0 }
            cache[url] = result
            bytes += result.count
        } else { if misses.count >= 100 { misses.removeAll() }; misses[url] = Date().addingTimeInterval(60) }
        return result
    }
}
private struct CompanyIcon<Fallback: View>: View {
    let url: URL
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback
    @State private var icon: UIImage?
    var body: some View {
        Group {
            if let icon { Image(uiImage: icon).resizable().scaledToFit().padding(max(3, size * 0.1)).background(.background) }
            else { fallback() }
        }.task(id: url) {
            if let data = await CompanyIconStore.shared.data(for: url), !Task.isCancelled,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceThumbnailMaxPixelSize: 96,
                   kCGImageSourceCreateThumbnailWithTransform: true
               ] as CFDictionary) { icon = UIImage(cgImage: image) }
        }
    }
}
