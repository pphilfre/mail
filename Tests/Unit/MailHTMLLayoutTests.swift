import XCTest
import WebKit
@testable import DispatchMail

@MainActor
final class MailHTMLLayoutTests: XCTestCase {
    func testFixedWidthHTMLFitsAndRefitsWhileEmailScriptsStayDisabled() async throws {
        let configuration = MailHTMLView.configuration()
        let heightObserver = HTMLHeightObserver()
        configuration.userContentController.add(heightObserver, contentWorld: .defaultClient, name: "mailLayout")
        XCTAssertFalse(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 800), configuration: configuration)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 800))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(web)
        window.makeKeyAndVisible()
        defer { web.stopLoading(); window.isHidden = true }
        let observer = HTMLLoadObserver()
        web.navigationDelegate = observer
        web.loadHTMLString(MailHTMLView.document("""
            <div style="width:640px;min-width:640px;height:600px">Wide receipt</div>
            <script>document.body.setAttribute('data-email-script', 'ran')</script>
            """, remoteImages: false), baseURL: nil)
        for _ in 0..<150 {
            if observer.didLoad { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(observer.didLoad, "Email must finish loading before layout is measured")
        try await assertFits(web, expectedWidth: 320)
        XCTAssertGreaterThan(heightObserver.height, 200)
        XCTAssertLessThan(heightObserver.height, 400, "Report scaled content height rather than the 800-point viewport")
        web.frame.size.width = 480
        web.layoutIfNeeded()
        try await assertFits(web, expectedWidth: 480)
    }

    private func assertFits(_ web: WKWebView, expectedWidth: Double) async throws {
        var metrics: [Double] = []
        for _ in 0..<50 {
            let json: String = try await withCheckedThrowingContinuation { continuation in
                web.evaluateJavaScript("JSON.stringify([document.documentElement.clientWidth, document.getElementById('dispatch-mail-body').getBoundingClientRect().width, document.getElementById('dispatch-mail-body').getBoundingClientRect().height, document.body.hasAttribute('data-email-script') ? 1 : 0])", in: nil, in: .defaultClient) { result in
                    switch result {
                    case .success(let value): continuation.resume(returning: value as? String ?? "[]")
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
            metrics = try JSONDecoder().decode([Double].self, from: Data(json.utf8))
            if metrics.count == 4 && abs(metrics[0] - expectedWidth) < 2 && abs(metrics[1] - expectedWidth) < 2 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(metrics.count, 4)
        guard metrics.count == 4 else { return }
        XCTAssertEqual(metrics[0], expectedWidth, accuracy: 2)
        XCTAssertLessThanOrEqual(metrics[1], expectedWidth + 2, "Fixed-width email must fit without horizontal clipping")
        XCTAssertGreaterThan(metrics[2], 200, "The full scaled body must retain its height")
        XCTAssertEqual(metrics[3], 0, "Sender-provided JavaScript must never execute")
    }
}

@MainActor
private final class HTMLHeightObserver: NSObject, WKScriptMessageHandler {
    var height: Double = 0
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        height = (message.body as? NSNumber)?.doubleValue ?? 0
    }
}

@MainActor
private final class HTMLLoadObserver: NSObject, WKNavigationDelegate {
    var didLoad = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { didLoad = true }
}
