import Foundation

enum IncomingMailShare: Equatable {
    case file(URL), link(URL), compose(to: String, subject: String, body: String)

    static func parse(_ url: URL) -> Self? {
        if url.isFileURL { return .file(url) }
        if ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return .link(url) }
        if url.scheme?.lowercased() == "mailto", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            func value(_ name: String) -> String { parts.queryItems?.first { $0.name.lowercased() == name }?.value ?? "" }
            return .compose(to: parts.path.removingPercentEncoding ?? parts.path, subject: value("subject"), body: value("body"))
        }
        // Google OAuth callbacks belong to ASWebAuthenticationSession, never the composer.
        return nil
    }
}
