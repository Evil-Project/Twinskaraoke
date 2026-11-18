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
    private var action: ((SplashWebsiteAction) -> Void)?
    private(set) var owner: UUID?
    private(set) var finished = false
    private(set) var interactionCount = 0

    func open(_ website: SplashWebsite, owner: UUID, action: @escaping (SplashWebsiteAction) -> Void) {
        guard self.owner == nil || self.owner == owner else { return }
        stop()
        self.owner = owner
        finished = false
        self.action = action
        failure = nil
        loading = true
        var isFixture = website.url.isEmpty
        #if DEBUG
        // UI automation must never contact a release endpoint, including through Studio drafts.
        if AppRuntime.isUITestMode { isFixture = true }
        #endif
        let url = website.url.isEmpty ? URL(string: "https://splash-fixture.invalid/form") : website.httpsURL
        guard let url, let session = SplashWebsiteHandshake(url: url) else {
            failure = .unavailable
            return
        }
        handshake = session

        let controller = WKUserContentController()
        // Keep necessary form scrolling, while preventing rubber-band/pull overscroll.
        controller.addUserScript(WKUserScript(source: """
            document.documentElement.style.overscrollBehavior = "none";
            if (document.body) document.body.style.overscrollBehavior = "none";
            document.addEventListener("click", () => {
                window.webkit.messageHandlers.splashInteraction.postMessage("tap");
            }, { capture: true, passive: true });
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.add(Bridge { [weak self] message in self?.receive(message, sessionID: session.id) }, name: Bridge.name)
        controller.add(Bridge { [weak self] message in
            guard let self, self.handshake?.id == session.id, message.frameInfo.isMainFrame,
                  message.webView?.configuration.userContentController === self.controller else { return }
            let security = message.frameInfo.securityOrigin
            let origin = SplashWebsiteHandshake.Origin(scheme: security.protocol, host: security.host,
                                                       port: security.port == 0 ? nil : security.port)
            guard origin == session.origin else { return }
            self.interactionCount += 1
        }, name: "splashInteraction")
        self.controller = controller

        var configuration = WebPage.Configuration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        let decider = SplashWebsiteNavigationPolicy(origin: session.origin) { [weak self] error in
            self?.fail(error, sessionID: session.id)
        }
        let page = WebPage(configuration: configuration, navigationDecider: decider)
        self.page = page
        let events = page.navigations
        observation = Task { [weak self] in
            do {
                for try await event in events {
                    if event == .receivedServerRedirect { decider.receivedServerRedirect() }
                    guard event == .finished else { continue }
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

    func stop(owner: UUID) {
        guard self.owner == owner else { return }
        stop()
    }

    /// Native continuation and script completion share the same single-use action.
    func continueForNow(owner: UUID) {
        guard self.owner == owner, let action else { return }
        finished = true
        stop()
        action(.deferred)
    }

    private func stop() {
        handshake = nil
        action = nil
        owner = nil
        timeout?.cancel()
        timeout = nil
        observation?.cancel()
        observation = nil
        controller?.removeScriptMessageHandler(forName: Bridge.name)
        controller?.removeScriptMessageHandler(forName: "splashInteraction")
        controller = nil
        let previousPage = page
        page = nil
        previousPage?.stopLoading()
    }

    private func receive(_ message: WKScriptMessage, sessionID: String) {
        guard page != nil, message.webView?.configuration.userContentController === controller,
              handshake?.id == sessionID, let data = message.body as? [String: Any],
              let type = data["type"] as? String, let outcome = SplashWebsiteAction(rawValue: type)
        else { return }
        let security = message.frameInfo.securityOrigin
        let origin = SplashWebsiteHandshake.Origin(scheme: security.protocol, host: security.host,
                                                   port: security.port == 0 ? nil : security.port)
        guard handshake?.consume(type: data["type"] as? String, id: data["id"] as? String,
                                 isMainFrame: message.frameInfo.isMainFrame, origin: origin) == true
        else { return }
        let action = action
        finished = true
        stop()
        action?(outcome)
    }

    private func fail(_ error: Failure, sessionID: String) {
        guard handshake?.id == sessionID else { return }
        if error == .closed { finished = true }
        let action = action
        let owner = owner
        stop()
        self.owner = owner
        self.action = action
        loading = false
        failure = error
        if error == .closed { action?(.closed) }
    }

    /// Closed campaigns are terminal; temporary HTTP and unsupported-content failures allow retry.
    static func failure(for response: URLResponse, canShowMimeType: Bool) -> Failure? {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 410 { return .closed }
        if status >= 400 || !canShowMimeType { return .unavailable }
        return nil
    }

    private final class Bridge: NSObject, WKScriptMessageHandler {
        static let name = "splashCompletion"
        let receive: (WKScriptMessage) -> Void

        init(receive: @escaping (WKScriptMessage) -> Void) { self.receive = receive }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            receive(message)
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
          button, input { font: inherit; box-sizing: border-box; max-inline-size: 100%; }
          button { font: inherit; padding: .65rem 1rem; overflow-wrap: anywhere; }
          input { display: block; width: 100%; }
        </style>
        <title>Website test</title>
        <h1>Website test</h1>
        <p><label>Optional feedback <input id="feedback" autocomplete="off"></label></p>
        <button type="button" id="fail">Simulate failed submission</button>
        <p id="status" role="status"></p>
        <button type="button" id="complete">Complete test page</button>
        <button type="button" id="cancel">Cancel test form</button>
        <script>
          let id = new URLSearchParams(location.hash.slice(1)).get("splashSession");
          history.replaceState(null, "", location.pathname + location.search);
          document.getElementById("fail").addEventListener("click", () => {
            document.getElementById("status").textContent = "Submission failed. Please try again.";
          });
          function finish(type) {
            const completion = window.webkit?.messageHandlers?.splashCompletion;
            if (!completion || !id) return;
            completion.postMessage({ type, id });
            id = null;
          }
          document.getElementById("complete").addEventListener("click", () => finish("completed"));
          document.getElementById("cancel").addEventListener("click", () => finish("canceled"));
        </script>
        </html>
        """
}
