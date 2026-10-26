import Foundation

nonisolated struct Artist: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String?
    let imagePath: String?
    let songCount: Int?
    let songListDTOs: [Song]?
    var imageURL: URL? {
        artistImageURL(variant: .thumbnail)
    }

    var rowImageURL: URL? {
        artistImageURL(variant: .row)
    }

    private func artistImageURL(variant: ArtworkImageVariant) -> URL? {
        guard let path = imagePath, !path.isEmpty else { return nil }
        return ArtworkURLBuilder.storageResizedURL(path: path, variant: variant)
            ?? URL(string: StorageHost.base + ArtworkURLBuilder.normalizedPath(path))
    }

    static func == (lhs: Artist, rhs: Artist) -> Bool {
        lhs.id == rhs.id
    }
}
