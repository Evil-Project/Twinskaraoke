import Foundation
import Observation
import WebKit

@MainActor @Observable final class SplashWebsiteSession {
    enum Failure { case unavailable, closed }

    private(set) var page: WebPage?
    private(set) var loading = true
    private(set) var failure: Failure?
    private var handshake: SplashWebsiteHandshake?
    private var observation: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var controller: WKUserContentController?
    private var advance: (() -> Void)?

    func open(_ website: SplashWebsite, advance: @escaping () -> Void) {
        stop()
        failure = nil
        loading = true
        let isFixture = website.url.isEmpty
        let url = isFixture ? URL(string: "https://splash-fixture.invalid/form") : website.httpsURL
        guard let url, let session = SplashWebsiteHandshake(url: url) else {
            failure = .unavailable
            return
        }
        handshake = session
        self.advance = advance

        let controller = WKUserContentController()
        controller.add(Bridge { [weak self] message in self?.receive(message, sessionID: session.id) }, name: Bridge.name)
        self.controller = controller

        var configuration = WebPage.Configuration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        let decider = Navigation(origin: session.origin) { [weak self] error in
            self?.fail(error, sessionID: session.id)
        }
        let page = WebPage(configuration: configuration, navigationDecider: decider)
        self.page = page
        let events = page.navigations
        observation = Task { [weak self] in
            do {
                for try await event in events where event == .finished {
                    guard let self, self.handshake?.id == session.id else { return }
                    self.loading = false
                    self.timeout?.cancel()
                }
            } catch {
                self?.fail(.unavailable, sessionID: session.id)
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
            self?.fail(.unavailable, sessionID: session.id)
        }
        let request = URLRequest(url: session.requestURL, cachePolicy: .reloadIgnoringLocalCacheData)
        if isFixture {
            page.load(simulatedRequest: request, responseHTML: Self.fixture)
        } else {
            page.load(request)
        }
    }

    func stop() {
        handshake = nil
        advance = nil
        timeout?.cancel()
        timeout = nil
        observation?.cancel()
        observation = nil
        controller?.removeScriptMessageHandler(forName: Bridge.name)
        controller = nil
        let previousPage = page
        page = nil
        previousPage?.stopLoading()
    }

    private func receive(_ message: WKScriptMessage, sessionID: String) {
        guard handshake?.id == sessionID, let data = message.body as? [String: Any] else { return }
        let security = message.frameInfo.securityOrigin
        let origin = SplashWebsiteHandshake.Origin(scheme: security.protocol, host: security.host,
                                                   port: security.port == 0 ? nil : security.port)
        guard handshake?.consume(type: data["type"] as? String, id: data["id"] as? String,
                                 isMainFrame: message.frameInfo.isMainFrame, origin: origin) == true
        else { return }
        let action = advance
        stop()
        action?()
    }

    private func fail(_ error: Failure, sessionID: String) {
        guard handshake?.id == sessionID else { return }
        failure = error
        stop()
    }

    private final class Bridge: NSObject, WKScriptMessageHandler {
        static let name = "splashCompletion"
        let receive: (WKScriptMessage) -> Void

        init(receive: @escaping (WKScriptMessage) -> Void) { self.receive = receive }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            receive(message)
        }
    }

    private struct Navigation: WebPage.NavigationDeciding {
        let origin: SplashWebsiteHandshake.Origin
        let fail: (Failure) -> Void
        private var mainURL: URL?

        init(origin: SplashWebsiteHandshake.Origin, fail: @escaping (Failure) -> Void) {
            self.origin = origin
            self.fail = fail
        }

        mutating func decidePolicy(
            for action: WebPage.NavigationAction,
            preferences _: inout WebPage.NavigationPreferences
        ) async -> WKNavigationActionPolicy {
            guard let target = action.target else { return .cancel }
            guard target.isMainFrame else { return .allow }
            guard let url = action.request.url, SplashWebsiteHandshake.Origin(url) == origin, !action.shouldPerformDownload
            else { return .cancel }
            mainURL = withoutFragment(url)
            return .allow
        }

        func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
            guard let url = response.response.url, withoutFragment(url) == mainURL,
                  let status = (response.response as? HTTPURLResponse)?.statusCode
            else { return .allow }
            if status == 410 {
                fail(.closed)
                return .cancel
            }
            if status >= 400 || !response.canShowMimeType {
                fail(.unavailable)
                return .cancel
            }
            return .allow
        }

        private func withoutFragment(_ url: URL) -> URL? {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            return components?.url
        }
    }

    private static let fixture = """
        <!doctype html>
        <html lang="en">
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: dark; background: #101827; color: white; font: -apple-system-body; }
          body { margin: 1.25rem; }
          button { font: inherit; padding: .65rem 1rem; }
        </style>
        <title>Website test</title>
        <h1>Website test</h1>
        <button type="button" id="complete">Complete test page</button>
        <script>
          let id = new URLSearchParams(location.hash.slice(1)).get("splashSession");
          history.replaceState(null, "", location.pathname + location.search);
          document.getElementById("complete").addEventListener("click", () => {
            const completion = window.webkit?.messageHandlers?.splashCompletion;
            if (!completion || !id) return;
            completion.postMessage({ type: "completed", id });
            id = null;
          });
        </script>
        </html>
        """
}
