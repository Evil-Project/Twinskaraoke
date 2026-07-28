import SwiftUI

struct FavoritesArtworkTile: View {
    var sizeFraction: CGFloat = 0.46
    private let cornerRadius: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Color(red: 0.94, green: 0.96, blue: 0.96)

                Image(systemName: "star.fill")
                    .font(.system(size: side * sizeFraction, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct PlaylistArtwork: View {
    let playlist: Playlist
    var cornerRadius: CGFloat = 10

    var body: some View {
        if playlist.isFavorites || canUseInitialArtwork {
            PlaylistArtworkContent(
                playlist: playlist,
                coverURLs: initialCoverURLs,
                cornerRadius: cornerRadius
            )
        } else {
            PlaylistCoverWithLoader(playlist: playlist, cornerRadius: cornerRadius)
        }
    }

    private var canUseInitialArtwork: Bool {
        if playlist.explicitCoverURL != nil {
            return true
        }
        return initialCoverURLs.count >= 4
    }

    private var initialCoverURLs: [URL] {
        if let url = playlist.explicitCoverURL {
            return [url]
        }
        return playlist.initialMosaicArtworkURLs
    }
}

struct PlaylistArtworkContent: View {
    let playlist: Playlist
    let coverURLs: [URL]
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if playlist.isFavorites {
                FavoritesArtworkTile()
            } else if let url = coverURLs.first, coverURLs.count == 1 {
                RemoteArtworkImage(url: url, cornerRadius: cornerRadius)
            } else if coverURLs.count > 1 {
                PlaylistMosaicArtwork(urls: coverURLs, cornerRadius: cornerRadius)
            } else {
                PlaylistPlaceholderArtwork(seed: playlist.id)
            }
        }
    }
}

private struct PlaylistCoverWithLoader: View {
    let playlist: Playlist
    let cornerRadius: CGFloat
    @StateObject private var loader = PlaylistCoverLoader()

    var body: some View {
        PlaylistArtworkContent(
            playlist: playlist,
            coverURLs: loader.artworkURLs,
            cornerRadius: cornerRadius
        )
        .onAppear {
            loader.load(playlistID: playlist.id, fallback: playlist.songListDTOs)
        }
        .onChange(of: playlist.id) { _, newID in
            loader.load(playlistID: newID, fallback: playlist.songListDTOs)
        }
    }
}

struct PlaylistMosaicArtwork: View {
    let urls: [URL]
    var cornerRadius: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 2
            LazyVGrid(
                columns: [
                    GridItem(.fixed(cell), spacing: 0),
                    GridItem(.fixed(cell), spacing: 0),
                ],
                spacing: 0
            ) {
                ForEach(0 ..< 4, id: \.self) { index in
                    if let url = artworkURL(at: index) {
                        let variant: ArtworkImageVariant = cell <= 80 ? .row : .thumbnail
                        let optimizedURL = ArtworkURLBuilder.variantURL(from: url, variant: variant) ?? url
                        RemoteArtworkImage(
                            url: optimizedURL,
                            cornerRadius: 0,
                            fixedDisplaySize: CGSize(width: cell, height: cell)
                        )
                            .frame(width: cell, height: cell)
                    } else {
                        PlaylistPlaceholderArtwork(seed: "\(index)-\(urls.count)")
                            .frame(width: cell, height: cell)
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func artworkURL(at index: Int) -> URL? {
        guard !urls.isEmpty else { return nil }
        return urls[index % urls.count]
    }
}

struct PlaylistPlaceholderArtwork: View {
    let seed: String

    var body: some View {
        GeometryReader { geo in
            MusicArtworkPlaceholder(cornerRadius: 0)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

extension Playlist {
    var explicitCoverURL: URL? {
        imageURL(variant: .card)
    }

    var explicitCoverThumbnailURL: URL? {
        imageURL(variant: .thumbnail)
    }

    var initialMosaicArtworkURLs: [URL] {
        let mosaicURLs = mosaicMedia?.compactMap { media -> URL? in
            Playlist.mediaURL(from: media, variant: .card)
        } ?? []
        if !mosaicURLs.isEmpty {
            return Playlist.uniqueURLs(mosaicURLs, limit: 4)
        }
        return Playlist.songArtworkURLs(songListDTOs ?? [], limit: 4)
    }

    static func mediaURL(from path: String) -> URL? {
        ArtworkURLBuilder.imageURL(cloudflareID: nil, path: path, variant: .card)
    }

    static func mediaURL(from path: String, variant: ArtworkImageVariant) -> URL? {
        ArtworkURLBuilder.imageURL(cloudflareID: nil, path: path, variant: variant)
    }

    static func mediaURL(from media: Media, variant: ArtworkImageVariant) -> URL? {
        ArtworkURLBuilder.imageURL(
            cloudflareID: media.cloudflareId,
            path: media.absolutePath,
            variant: variant
        )
    }

    static func uniqueURLs(_ urls: [URL], limit: Int) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            guard seen.insert(url.absoluteString).inserted else { continue }
            result.append(url)
            if result.count == limit { break }
        }
        return result
    }

    static func songArtworkURLs(_ songs: [Song], limit: Int) -> [URL] {
        var seenOwnArtwork = Set<String>()
        var result: [URL] = []
        for song in songs {
            guard let url = song.imageURL else { continue }
            if song.hasOwnArtwork {
                guard seenOwnArtwork.insert(url.absoluteString).inserted else { continue }
            }
            result.append(url)
            if result.count == limit { break }
        }
        return result
    }
}
