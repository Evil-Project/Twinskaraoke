#if os(iOS)
import Foundation

nonisolated enum AppRoute: Equatable, Sendable {
    case home, radio, search, library, nowPlaying, lyrics
    case song(String), playlist(String)

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "twinskaraoke", parts.user == nil,
              parts.password == nil, parts.port == nil, parts.query == nil, parts.fragment == nil,
              let host = parts.host else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        if host == "song" || host == "playlist" {
            guard path.count == 2, path[0].isEmpty,
                  let id = String(path[1]).removingPercentEncoding,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !id.contains("/"), !id.contains("\\"), id != ".", id != ".." else { return nil }
            self = host == "song" ? .song(id) : .playlist(id)
            return
        }
        guard parts.path.isEmpty || parts.path == "/" else { return nil }
        switch host {
        case "home": self = .home
        case "radio": self = .radio
        case "search": self = .search
        case "library": self = .library
        case "now-playing": self = .nowPlaying
        case "lyrics": self = .lyrics
        default: return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "twinskaraoke"
        switch self {
        case .home: components.host = "home"
        case .radio: components.host = "radio"
        case .search: components.host = "search"
        case .library: components.host = "library"
        case .nowPlaying: components.host = "now-playing"
        case .lyrics: components.host = "lyrics"
        case .song(let id): components.host = "song"; components.path = "/" + id
        case .playlist(let id): components.host = "playlist"; components.path = "/" + id
        }
        return components.url!
    }
}
#endif
