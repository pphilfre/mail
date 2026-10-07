import SwiftUI
import WebKit

/// Each message gets an isolated, nonpersistent web view with script execution disabled.
struct MailHTMLView: UIViewRepresentable {
    let html: String
    let remoteImages: Bool
    @Binding var height: CGFloat

    static func document(_ html: String, remoteImages: Bool) -> String {
        let images = remoteImages ? "https: data:" : "data:"
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
        let view = WKWebView(frame: .zero, configuration: Self.configuration())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        context.coordinator.observation = view.scrollView.observe(\.contentSize, options: [.new]) { [weak coordinator = context.coordinator] _, change in
            guard let size = change.newValue else { return }
            Task { @MainActor [weak coordinator] in
                guard let coordinator else { return }
                let newHeight = max(40, size.height)
                if abs(coordinator.height.wrappedValue - newHeight) > 1 {
                    coordinator.height.wrappedValue = newHeight
                }
            }
        }
        return view
    }
    static let fitScript = """
    (() => {
        const content = document.getElementById('dispatch-mail-body');
        if (!content) return;
        let pending = false;
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
        };
        const schedule = () => {
            if (!pending) { pending = true; requestAnimationFrame(fit); }
        };
        window.addEventListener('resize', schedule);
        document.addEventListener('load', schedule, true);
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
        coordinator.observation?.invalidate()
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var observation: NSKeyValueObservation?
        var document = ""
        init(height: Binding<CGFloat>) { self.height = height }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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

struct MailBodyView: View {
    let html: String?
    let text: String
    let remoteImages: Bool
    @State private var height: CGFloat = 80
    var body: some View {
        MailHTMLView(html: html ?? "<div style='white-space:pre-wrap'>\(Self.escape(text))</div>", remoteImages: remoteImages, height: $height)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
