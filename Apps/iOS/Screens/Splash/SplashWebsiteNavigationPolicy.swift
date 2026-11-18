import Foundation
import WebKit

@MainActor final class SplashWebsiteNavigationPolicy: WebPage.NavigationDeciding {
    let origin: SplashWebsiteHandshake.Origin
    let fail: (SplashWebsiteSession.Failure) -> Void
    private var mainURL: URL?
    private var subframeURLs: Set<URL> = []
    private var awaitingRedirectResponse = false

    init(origin: SplashWebsiteHandshake.Origin, fail: @escaping (SplashWebsiteSession.Failure) -> Void) {
        self.origin = origin
        self.fail = fail
    }

    func recordMainNavigation(to url: URL) -> Bool {
        guard SplashWebsiteHandshake.Origin(url) == origin else { return false }
        mainURL = withoutFragment(url)
        awaitingRedirectResponse = false
        return true
    }

    // WebPage exposes a redirect event before a final response, but not its target URL.
    // Capture that URL from the response instead of WebPage.url, which is nil before content loads.
    func receivedServerRedirect() {
        guard mainURL != nil else { return }
        awaitingRedirectResponse = true
    }

    func recordSubframeNavigation(to url: URL) {
        if let url = withoutFragment(url) { subframeURLs.insert(url) }
    }

    func failure(for response: URLResponse, canShowMimeType: Bool) -> SplashWebsiteSession.Failure? {
        guard let rawURL = response.url, let url = withoutFragment(rawURL), !subframeURLs.contains(url),
              url == mainURL || awaitingRedirectResponse else { return nil }
        guard SplashWebsiteHandshake.Origin(url) == origin else { return .unavailable }
        mainURL = url
        awaitingRedirectResponse = false
        return SplashWebsiteSession.failure(for: response, canShowMimeType: canShowMimeType)
    }

    func decidePolicy(for action: WebPage.NavigationAction, preferences _: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        guard let target = action.target, let url = action.request.url else { return .cancel }
        guard target.isMainFrame else {
            recordSubframeNavigation(to: url)
            return .allow
        }
        return !action.shouldPerformDownload && recordMainNavigation(to: url) ? .allow : .cancel
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        if let error = failure(for: response.response, canShowMimeType: response.canShowMimeType) {
            fail(error)
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
