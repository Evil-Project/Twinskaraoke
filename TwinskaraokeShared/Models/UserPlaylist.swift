import Foundation

nonisolated struct UserPlaylist: Codable, Identifiable, Hashable, Sendable {
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
            if let path = media?.absolutePath, !path.isEmpty {
                mediaArray = [Media(absolutePath: path)]
            }
        }
        let effectiveCount = songCount > 0 ? songCount : songListDTOs?.count ?? 0
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

nonisolated struct UserPlaylistMedia: Codable, Sendable {
    let id: String?
    let fileName: String?
    let contentType: String?
    let description: String?
    let credit: String?
    let cloudflareId: String?
    let mediaStorageType: Int?
    let absolutePath: String?
}

extension UserPlaylist {
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        createdBy = try values.decodeIfPresent(String.self, forKey: .createdBy)
        updatedBy = try values.decodeIfPresent(String.self, forKey: .updatedBy)
        media = try values.decodeIfPresent(UserPlaylistMedia.self, forKey: .media)
        createdAt = try values.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
        totalDuration = try values.decodeIfPresent(Int.self, forKey: .totalDuration)
        songCount = try values.decodeIfPresent(Int.self, forKey: .songCount) ?? 0
        playCount = try values.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        favoriteCount = try values.decodeIfPresent(Int.self, forKey: .favoriteCount)
        playlistType = try values.decodeIfPresent(Int.self, forKey: .playlistType)
        songListDTOs = try values.decodeIfPresent([Song].self, forKey: .songListDTOs)
        mosaicMedia = try values.decodeIfPresent([Media].self, forKey: .mosaicMedia)
        genres = try values.decodeIfPresent([String].self, forKey: .genres)
        editable = try values.decodeIfPresent(Bool.self, forKey: .editable) ?? false
        deletable = try values.decodeIfPresent(Bool.self, forKey: .deletable) ?? false
        isPublic = try values.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        isSetList = try values.decodeIfPresent(Bool.self, forKey: .isSetList) ?? false
        setListDate = try values.decodeIfPresent(String.self, forKey: .setListDate)
    }
}
