enum LibraryDestination: Hashable {
    case playlists
    case artists
    case songs
    case downloaded
    case artGallery
    case videoGallery
    case randomSongs
    case artist(Artist)
    case galleryArtist(GalleryArtist)
    case artwork(GalleryArt, artist: GalleryArtist)
    case video(GalleryVideo)

    static func == (lhs: LibraryDestination, rhs: LibraryDestination) -> Bool {
        switch (lhs, rhs) {
        case (.playlists, .playlists),
             (.artists, .artists),
             (.songs, .songs),
             (.downloaded, .downloaded),
             (.artGallery, .artGallery),
             (.videoGallery, .videoGallery),
             (.randomSongs, .randomSongs):
            true
        case let (.artist(lhsArtist), .artist(rhsArtist)):
            lhsArtist.id == rhsArtist.id
        case let (.galleryArtist(lhsArtist), .galleryArtist(rhsArtist)):
            lhsArtist.id == rhsArtist.id
        case let (.artwork(lhsArt, lhsArtist), .artwork(rhsArt, rhsArtist)):
            lhsArt.id == rhsArt.id && lhsArtist.id == rhsArtist.id
        case let (.video(lhsVideo), .video(rhsVideo)):
            lhsVideo.id == rhsVideo.id
        default:
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .playlists:
            hasher.combine(0)
        case .artists:
            hasher.combine(1)
        case .songs:
            hasher.combine(2)
        case .downloaded:
            hasher.combine(3)
        case .artGallery:
            hasher.combine(4)
        case .videoGallery:
            hasher.combine(5)
        case .randomSongs:
            hasher.combine(6)
        case let .artist(artist):
            hasher.combine(7)
            hasher.combine(artist.id)
        case let .galleryArtist(artist):
            hasher.combine(8)
            hasher.combine(artist.id)
        case let .artwork(art, artist):
            hasher.combine(9)
            hasher.combine(art.id)
            hasher.combine(artist.id)
        case let .video(video):
            hasher.combine(10)
            hasher.combine(video.id)
        }
    }
}
