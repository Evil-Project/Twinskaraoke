import SwiftUI
import WebKit

struct CaptchaWebView: UIViewRepresentable {
    let url: URL
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(allowedHost: url.host?.lowercased(), onClose: onClose)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let allowedHost: String?
        let onClose: () -> Void
        init(allowedHost: String?, onClose: @escaping () -> Void) {
            self.allowedHost = allowedHost
            self.onClose = onClose
        }

        func webViewDidClose(_: WKWebView) {
            DispatchQueue.main.async { self.onClose() }
        }

        // The full-screen web view may only navigate within the captcha host;
        // anything else is cancelled and handed to the system browser.
        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame ?? true,
                  let target = navigationAction.request.url,
                  let scheme = target.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  target.host?.lowercased() != allowedHost
            else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            UIApplication.shared.open(target)
        }
    }
}
