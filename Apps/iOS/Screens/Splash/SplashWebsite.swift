import Foundation

nonisolated struct SplashWebsite: Codable, Equatable {
    var url = ""

    var httpsURL: URL? {
        guard let components = URLComponents(string: url),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true
        else { return nil }
        return components.url
    }
}
