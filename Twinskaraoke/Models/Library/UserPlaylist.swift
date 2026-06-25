import Foundation

struct UserPlaylist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let createdBy: String?
    let updatedBy: String?
    let media: UserPlaylistMedia?
    let createdAt: String?
    let updatedAt: String?
    let totalDuration: Int?
    let songCount: Int
    let playCount: Int
    let favoriteCount: Int?
    let playlistType: Int?
    let songListDTOs: [Song]?
    let mosaicMedia: [Media]?
    let genres: [String]?
    let editable: Bool
    let deletable: Bool
    let isPublic: Bool
    let isSetList: Bool
    let setListDate: String?

    static func == (lhs: UserPlaylist, rhs: UserPlaylist) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func asPlaylist() -> Playlist {
        var mediaArray: [Media]? = mosaicMedia
        if mediaArray == nil || mediaArray?.isEmpty == true {
            if let cfId = media?.cloudflareId, !cfId.isEmpty {
                mediaArray = [Media(absolutePath: "/\(cfId)")]
            } else if let path = media?.absolutePath, !path.isEmpty {
                mediaArray = [Media(absolutePath: path)]
            }
        }
        let effectiveCount = max(songCount, songListDTOs?.count ?? 0)
        var p = Playlist(
            id: id,
            name: name,
            songCount: effectiveCount,
            media: media.map { PlaylistMedia(cloudflareId: $0.cloudflareId, absolutePath: $0.absolutePath) },
            mosaicMedia: mediaArray,
            songListDTOs: songListDTOs
        )
        p.isPersonal = true
        return p
    }
}

struct UserPlaylistMedia: Codable {
    let id: String?
    let fileName: String?
    let contentType: String?
    let description: String?
    let credit: String?
    let cloudflareId: String?
    let mediaStorageType: Int?
    let absolutePath: String?
}
