import SwiftUI
import ImageIO

/// Decorative identity only; logos never indicate that a sender is verified.
struct SenderAvatar: View {
    let email: String
    let name: String
    var allowsRemoteIcon = true
    var size: CGFloat = 38
    var context = ""
    @AppStorage("senderPictures") private var senderPictures = true
    @State private var icon: UIImage?
    @State private var resolvedKey = ""
    private var requestKey: String { "\(allowsRemoteIcon && senderPictures)-\(email.lowercased())" }
    private var category: LocalMailCategory { SenderIdentity.category(email: email, context: context) }
    private var appearance: (String, Color) {
        switch category {
        case .finance: ("creditcard", .green)
        case .travel: ("airplane", .teal)
        case .newsletters: ("newspaper", .indigo)
        case .promotions: ("tag", .orange)
        case .work: ("briefcase", .blue)
        case .personal: ("person.crop.circle", .secondary)
        case .other: ("envelope", .secondary)
        }
    }
    var body: some View {
        Group {
            if let icon, resolvedKey == requestKey {
                Image(uiImage: icon).resizable().scaledToFit().padding(max(3, size * 0.1)).background(MailStyle.paper)
            } else {
                Image(systemName: appearance.0).font(.system(size: size * 0.48, weight: .regular))
                    .foregroundStyle(appearance.1).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appearance.1.opacity(0.09))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 11))
        .accessibilityHidden(true)
        .task(id: requestKey) {
            icon = nil; resolvedKey = ""
            let key = requestKey
            guard allowsRemoteIcon, senderPictures else { return }
            // Domain parsing and resource loading happen off the UI actor.
            let senderEmail = email
            let domains = await Task.detached(priority: .utility) { SenderIdentity.iconDomains(email: senderEmail) }.value
            for domain in domains {
                guard !Task.isCancelled, let url = URL(string: "https://\(domain)/favicon.ico") else { return }
                if let data = await CompanyIconStore.shared.data(for: url), !Task.isCancelled,
                   let image = UIImage(data: data) { resolvedKey = key; icon = image; return }
            }
        }
    }
}

private actor CompanyIconStore {
    static let shared = CompanyIconStore()
    private var cache: [URL: Data] = [:]
    private var requests: [URL: Task<Data?, Never>] = [:]
    private var misses: [URL: Date] = [:]
    private var bytes = 0
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 4_000_000, diskCapacity: 20_000_000, diskPath: "DispatchSenderIcons")
        return URLSession(configuration: configuration)
    }()
    func data(for url: URL) async -> Data? {
        if let data = cache[url] { return data }
        if let until = misses[url], until > Date() { return nil }
        if let request = requests[url] { return await request.value }
        let session = session
        let request = Task<Data?, Never> {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (stream, response) = try? await session.bytes(for: request),
                  let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.scheme == "https", response.expectedContentLength <= 1_000_000 else { return nil }
            var data = Data()
            do {
                for try await byte in stream {
                    guard data.count < 1_000_000 else { return nil }
                    data.append(byte)
                }
            } catch { return nil }
            // Decode before caching. HTML error pages and broken icons must fall through to the root domain.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 1, height > 1, width <= 4096, height <= 4096,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 96,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary), image.width > 1, image.height > 1 else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return output as Data
        }
        requests[url] = request
        let result = await request.value
        requests[url] = nil
        if let result {
            if cache.count >= 200 || bytes + result.count > 8_000_000 { cache.removeAll(keepingCapacity: true); bytes = 0 }
            cache[url] = result; bytes += result.count
        } else {
            if misses.count >= 300 { misses.removeAll() }
            misses[url] = Date().addingTimeInterval(3600)
        }
        return result
    }
}
