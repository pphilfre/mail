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
    private var symbol: String {
        switch category {
        case .finance: "creditcard"
        case .travel: "airplane"
        case .newsletters: "newspaper"
        case .promotions: "tag"
        case .work: "briefcase"
        case .personal: "person.crop.circle"
        case .other: "envelope"
        }
    }
    var body: some View {
        Group {
            if let icon, resolvedKey == requestKey {
                Image(uiImage: icon).resizable().scaledToFit().padding(max(4, size * 0.14)).background(MailStyle.tile)
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.48, weight: .regular))
                    .foregroundStyle(MailStyle.secondaryInk).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MailStyle.tile)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: MailStyle.controlRadius))
        .overlay { RoundedRectangle(cornerRadius: MailStyle.controlRadius).strokeBorder(MailStyle.divider.opacity(0.5), lineWidth: 0.5) }
        .accessibilityHidden(true)
        .task(id: requestKey) {
            icon = nil; resolvedKey = ""
            let key = requestKey
            guard allowsRemoteIcon, senderPictures else { return }
            // Domain parsing and resource loading happen off the UI actor.
            let senderEmail = email
            let urls = await Task.detached(priority: .utility) { SenderIdentity.iconURLs(email: senderEmail) }.value
            for url in urls {
                guard !Task.isCancelled else { return }
                if let data = await CompanyIconStore.shared.data(for: url), !Task.isCancelled,
                   let image = UIImage(data: data) { resolvedKey = key; icon = image; return }
            }
            if let host = urls.first?.host {
                for url in await CompanyIconStore.shared.declaredIcons(host: host) {
                    guard !Task.isCancelled else { return }
                    if let data = await CompanyIconStore.shared.data(for: url), let image = UIImage(data: data) {
                        guard !Task.isCancelled else { return }
                        resolvedKey = key; icon = image; return
                    }
                }
            }
        }
    }
}

private actor CompanyIconStore {
    static let shared = CompanyIconStore()
    private var cache: [URL: Data] = [:]
    private var requests: [URL: Task<Data?, Never>] = [:]
    private var misses: [URL: Date] = [:]
    private var discoveries: [String: [URL]] = [:]
    private var discoveryRequests: [String: Task<[URL], Never>] = [:]
    private var bytes = 0
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 4_000_000, diskCapacity: 20_000_000, diskPath: "DispatchSenderIcons")
        return URLSession(configuration: configuration)
    }()
    func declaredIcons(host: String) async -> [URL] {
        if let urls = discoveries[host] { return urls }
        if let job = discoveryRequests[host] { return await job.value }
        let session = session
        let job = Task<[URL], Never> {
            guard let page = URL(string: "https://\(host)/") else { return [] }
            var request = URLRequest(url: page, timeoutInterval: 5)
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            guard let (stream, response) = try? await session.bytes(for: request),
                  let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let final = response.url, final.scheme == "https", response.expectedContentLength <= 256_000 else { return [] }
            var data = Data()
            do {
                for try await byte in stream {
                    guard data.count < 256_000 else { return [] }; data.append(byte)
                }
            } catch { return [] }
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            // Resolve against the sender's root, so redirects cannot authorise unrelated icon hosts.
            return SenderIdentity.declaredIconURLs(html: html, page: page)
        }
        discoveryRequests[host] = job
        let urls = await job.value
        discoveryRequests[host] = nil
        if discoveries.count >= 200 { discoveries.removeAll() }
        discoveries[host] = urls
        return urls
    }
    func data(for url: URL) async -> Data? {
        if let data = cache[url] { return data }
        if let until = misses[url], until > Date() { return nil }
        if let request = requests[url] { return await request.value }
        let session = session
        let request = Task<Data?, Never> {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4)
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
