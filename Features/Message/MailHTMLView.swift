import SwiftUI
import WebKit

/// Each message gets an isolated, nonpersistent web view with script execution disabled.
struct MailHTMLView: UIViewRepresentable {
    let html: String
    let remoteImages: Bool
    @Binding var height: CGFloat

    static func document(_ html: String, remoteImages: Bool) -> String {
        let images = remoteImages ? "https: data:" : "data:"
        let html = removingTrackingPixels(html)
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src \(images); font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; padding: 0; width: 100%; font: -apple-system-body; overflow-wrap: anywhere; -webkit-user-select: text; user-select: text; }
        img { max-width: 100% !important; height: auto; }
        table { max-width: 100% !important; }
        pre { white-space: pre-wrap; }
        a { color: #007aff; }
        </style></head><body><div id="dispatch-mail-body">\(html)</div></body></html>
        """
    }
    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    static func removingTrackingPixels(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<img\b[^>]*>"#) else { return html }
        var output = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            if tag.range(of: #"(?i)(?:width|height)\s*=\s*["']?1(?:["'\s>]|px)|(?:width|height)\s*:\s*1px"#, options: .regularExpression) != nil {
                output.replaceSubrange(range, with: "")
            }
        }
        return output
    }
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        // App-owned layout code runs in an isolated world. Email scripts remain disabled by both preferences and CSP.
        configuration.userContentController.addUserScript(WKUserScript(source: Self.fitScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        return configuration
    }
    func makeUIView(context: Context) -> WKWebView {
        let view = MailWebViewPool.take()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.configuration.userContentController.add(context.coordinator, contentWorld: .defaultClient, name: "mailLayout")
        return view
    }
    static let fitScript = """
    (() => {
        const content = document.getElementById('dispatch-mail-body');
        if (!content) return;
        let pending = false;
        let lastHeight = 0;
        let lastWidth = 0;
        const report = () => {
            const height = content.getBoundingClientRect().height;
            if (height > 0 && Math.abs(height - lastHeight) > 1) {
                lastHeight = height;
                window.webkit?.messageHandlers?.mailLayout?.postMessage(height);
            }
        };
        const fit = () => {
            pending = false;
            const width = document.documentElement.clientWidth;
            if (width <= 0) return;
            content.style.zoom = '1';
            content.style.width = width + 'px';
            const naturalWidth = Math.max(width, content.scrollWidth);
            const scale = Math.min(1, width / naturalWidth);
            content.style.width = naturalWidth + 'px';
            content.style.zoom = String(scale);
            lastWidth = width;
            report();
        };
        const schedule = () => {
            if (!pending) { pending = true; requestAnimationFrame(fit); }
        };
        window.addEventListener('resize', () => {
            if (document.documentElement.clientWidth !== lastWidth) schedule();
            else report();
        });
        document.addEventListener('load', schedule, true);
        new ResizeObserver(() => requestAnimationFrame(report)).observe(content);
        fit();
    })();
    """
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.height = $height
        let document = Self.document(html, remoteImages: remoteImages)
        guard context.coordinator.document != document else { return }
        context.coordinator.document = document
        view.loadHTMLString(document, baseURL: nil)
    }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mailLayout", contentWorld: .defaultClient)
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        MailWebViewPool.put(uiView)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var document = ""
        init(height: Binding<CGFloat>) { self.height = height }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            let value = max(40, CGFloat(number.doubleValue))
            guard value.isFinite, abs(height.wrappedValue - value) > 1 else { return }
            height.wrappedValue = value
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
               ["https", "http", "mailto", "tel"].contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else if navigationAction.request.url?.absoluteString == "about:blank" {
                decisionHandler(.allow)
            } else { decisionHandler(.cancel) }
        }
    }
}

/// Keep a small number of warm renderers; each retains its own ephemeral data store.
@MainActor enum MailWebViewPool {
    private static var views: [WKWebView] = []
    private static var prepared = false
    static func prepare() {
        guard !prepared else { return }
        prepared = true
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 80), configuration: MailHTMLView.configuration())
        view.loadHTMLString("<html><body></body></html>", baseURL: nil)
        views.append(view)
    }
    static func take() -> WKWebView {
        views.popLast() ?? WKWebView(frame: .zero, configuration: MailHTMLView.configuration())
    }
    static func put(_ view: WKWebView) {
        view.loadHTMLString("<html><body></body></html>", baseURL: nil)
        view.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in if views.count < 2 { views.append(view) } }
        }
    }
}

@MainActor enum MailPlainText {
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 64; cache.totalCostLimit = 2_000_000
        return cache
    }()
    static func linked(_ text: String) -> AttributedString {
        let key = text as NSString
        let value: NSAttributedString
        if let cached = cache.object(forKey: key) { value = cached }
        else {
            let result = NSMutableAttributedString(string: text)
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
                for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let url = match.url ?? match.phoneNumber.flatMap { URL(string: "tel:" + $0.filter { $0.isNumber || $0 == "+" }) }
                    if let url, ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                        result.addAttribute(.link, value: url, range: match.range)
                    }
                }
            }
            value = result; cache.setObject(value, forKey: key, cost: text.utf8.count)
        }
        return (try? AttributedString(value)) ?? AttributedString(text)
    }
}

struct MailBodyView: View {
    let html: String?
    let text: String
    let remoteImages: Bool
    @State private var height: CGFloat = 80
    var body: some View {
        if let html, !html.isEmpty {
        MailHTMLView(html: html, remoteImages: remoteImages, height: $height)
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            Text(MailPlainText.linked(text)).font(.body).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
