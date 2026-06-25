import Foundation

nonisolated struct Artist: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String?
    let imagePath: String?
    let songCount: Int?
    let songListDTOs: [Song]?
    var imageURL: URL? {
        guard let path = imagePath, !path.isEmpty else { return nil }
        let cleanPath = path.hasPrefix("/") ? path : "/" + path
        return URL(string: StorageHost.base + cleanPath)
    }

    static func == (lhs: Artist, rhs: Artist) -> Bool {
        lhs.id == rhs.id
    }
}
