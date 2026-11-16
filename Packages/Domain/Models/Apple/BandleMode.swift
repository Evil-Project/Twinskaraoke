import Foundation

nonisolated enum BandleMode: Int, Codable, CaseIterable, Identifiable, Sendable {
    case normal = 0
    case extreme = 1

    var id: Int { rawValue }

    var queryItem: URLQueryItem {
        URLQueryItem(name: "mode", value: String(rawValue))
    }
}
