import SwiftUI
import WebKit

struct CaptchaWebView: View {
    let url: URL
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var page: WebPage?
    @State private var closeBridge = CloseBridge()

    var body: some View {
        Group {
            if let page {
                WebView(page)
                    .scrollDisabled(true)
                    .scrollBounceBehavior(.basedOnSize)
                    .webViewBackForwardNavigationGestures(.disabled)
            } else {
                Color.clear
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard page == nil else { return }
        closeBridge.onClose = onClose

        // The page dismisses itself with `window.close()`. WebPage has no
        // counterpart to WKUIDelegate's `webViewDidClose`, so the call is
        // forwarded through a script message instead.
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: "window.close = function () { window.webkit.messageHandlers.\(CloseBridge.name).postMessage(null); };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.add(closeBridge, name: CloseBridge.name)

        var configuration = WebPage.Configuration()
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        configuration.userContentController = controller

        let decider = HostRestrictedNavigation(allowedHost: url.host?.lowercased()) { target in
            openURL(target)
        }
        let page = WebPage(configuration: configuration, navigationDecider: decider)
        page.load(URLRequest(url: url))
        self.page = page
    }

    @MainActor
    final class CloseBridge: NSObject, WKScriptMessageHandler {
        static let name = "twinsClose"
        var onClose: (() -> Void)?

        func userContentController(_: WKUserContentController, didReceive _: WKScriptMessage) {
            onClose?()
        }
    }

    // The full-screen web view may only navigate within the captcha host;
    // anything else is cancelled and handed to the system browser.
    private struct HostRestrictedNavigation: WebPage.NavigationDeciding {
        let allowedHost: String?
        let openExternally: (URL) -> Void

        func decidePolicy(
            for action: WebPage.NavigationAction,
            preferences _: inout WebPage.NavigationPreferences
        ) async -> WKNavigationActionPolicy {
            guard action.target?.isMainFrame ?? true,
                  let target = action.request.url,
                  let scheme = target.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  target.host?.lowercased() != allowedHost
            else {
                return .allow
            }
            openExternally(target)
            return .cancel
        }
    }
}
