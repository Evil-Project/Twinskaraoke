import Foundation

nonisolated struct SplashWebsiteHandshake {
    let id = UUID().uuidString
    let origin: Origin
    let requestURL: URL
    private var completed = false

    init?(url: URL) {
        guard let origin = Origin(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.fragment = "splashSession=\(id)"
        guard let requestURL = components.url else { return nil }
        self.origin = origin
        self.requestURL = requestURL
    }

    mutating func consume(type: String?, id: String?, isMainFrame: Bool, origin: Origin?) -> Bool {
        guard !completed, isMainFrame, origin == self.origin, type == "completed", id == self.id else { return false }
        completed = true
        return true
    }

    nonisolated struct Origin: Equatable {
        let host: String
        let port: Int

        init?(scheme: String, host: String, port: Int?) {
            guard scheme.lowercased() == "https", !host.isEmpty else { return nil }
            self.host = host.lowercased()
            self.port = port ?? 443
        }

        init?(_ url: URL) {
            guard let scheme = url.scheme, let host = url.host(percentEncoded: false) else { return nil }
            self.init(scheme: scheme, host: host, port: url.port)
        }
    }
}
