import Foundation
import Testing
@testable import Twinskaraoke

private actor UploadedSongLoaderProbe {
    private var calls = 0

    func load() -> [Song] {
        calls += 1
        return []
    }

    func callCount() -> Int {
        calls
    }
}

@Suite("Song model")
struct SongModelTests {
    private func useGlobalStorageRegion() {
        UserDefaults.standard.set("global", forKey: "nk.storageRegion")
    }

    @Test("Artwork prefetch signatures ignore ordering and duplicates")
    @MainActor
    func artworkPrefetchSignatureUsesURLSets() {
        useGlobalStorageRegion()
        let first = Song(
            id: "song-1",
            title: "First",
            duration: 180,
            absolutePath: "/audio/first.mp3",
            cloudflareID: "first-image",
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: false
        )
        let second = Song(
            id: "song-2",
            title: "Second",
            duration: 180,
            absolutePath: "/audio/second.mp3",
            cloudflareID: "second-image",
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: false
        )

        let ordered = ArtworkPrefetchSignature(songs: [first, second, first], playlists: [])
        let reordered = ArtworkPrefetchSignature(songs: [second, first], playlists: [])

        #expect(ordered == reordered)
        #expect(ordered.songURLs.count == 2)
    }

    @Test("Cloudflare artwork URLs use the image CDN")
    func songImageURLWithCloudflareId() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-1",
            title: "Test Song",
            duration: 185,
            absolutePath: "/audio/test.mp3",
            cloudflareID: "image-id",
            coverArt: Media(absolutePath: "/covers/test.jpg"),
            originalArtists: ["Original Artist"],
            coverArtists: ["Cover Artist"],
            userUploaded: false
        )

        #expect(
            song.imageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=480,quality=85,format=webp/image-id/public"
        )
        #expect(
            song.rowImageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=180,quality=78,format=webp/image-id/public"
        )
        #expect(
            song.thumbnailURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=240,quality=80,format=webp/image-id/public"
        )
        #expect(
            song.heroImageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=960,quality=88,format=webp/image-id/public"
        )
        #expect(
            song.fullHDImageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=1920,quality=90,format=webp/image-id/public"
        )
    }

    @Test("downloadCoverImageURL produces a WebP URL for songs with artwork")
    func downloadCoverImageURLWithArtwork() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-1",
            title: "Test Song",
            duration: 185,
            absolutePath: "/audio/test.mp3",
            cloudflareID: "image-id",
            coverArt: Media(absolutePath: "/covers/test.jpg"),
            originalArtists: ["Original Artist"],
            coverArtists: ["Cover Artist"],
            userUploaded: false
        )

        #expect(
            song.downloadCoverImageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=1920,quality=90,format=webp/image-id/public"
        )
    }

    @Test("ArtworkURLBuilder upgrades Cloudflare delivery URLs to the resize route")
    func artworkVariantURLUsesCloudflareResizeRoute() throws {
        useGlobalStorageRegion()
        let legacyURL = try #require(
            URL(string: "https://images.neurokaraoke.com/account-hash/image-id/width=180,quality=78,format=webp")
        )
        let resizedURL = ArtworkURLBuilder.variantURL(from: legacyURL, variant: .card)

        #expect(
            resizedURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=480,quality=85,format=webp/account-hash/image-id/public"
        )
    }

    @Test("ArtworkURLBuilder keeps storage artwork on the storage resize route")
    func artworkVariantURLKeepsStorageResizeRoute() throws {
        useGlobalStorageRegion()
        let storageURL = try #require(
            URL(string: "https://storage.neurokaraoke.com/cdn-cgi/image/width=180,quality=78,format=webp/media/artist/example.png")
        )
        let resizedURL = ArtworkURLBuilder.variantURL(from: storageURL, variant: .card)

        #expect(
            resizedURL?.absoluteString
                == "https://storage.neurokaraoke.com/cdn-cgi/image/width=480,quality=85,format=webp/media/artist/example.png"
        )
    }

    @Test("ArtworkURLBuilder leaves unsupported artwork hosts unchanged")
    func artworkVariantURLLeavesUnsupportedHostsUnchanged() throws {
        let externalURL = try #require(
            URL(string: "https://cdn.example.com/artwork/image.jpg")
        )
        let resizedURL = ArtworkURLBuilder.variantURL(from: externalURL, variant: .thumbnail)

        #expect(resizedURL == externalURL)
    }

    @Test("downloadCoverImageURL is nil for songs without their own artwork")
    func downloadCoverImageURLWithoutArtwork() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-2",
            title: "Test Song",
            duration: 61,
            absolutePath: "/songs/test.mp3",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: false
        )

        #expect(song.downloadCoverImageURL == nil)
    }

    @Test("Audio URLs trim leading slashes")
    func songAudioURLNormalizesAbsolutePath() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-2",
            title: "Test Song",
            duration: 61,
            absolutePath: "/songs/test.mp3",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: false
        )

        #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/songs/test.mp3")
        #expect(song.durationText == "1:01")
    }

    @Test("audioURL falls back to oss when absolutePath is nil")
    func songAudioURLFallsBackToOss() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-oss",
            title: "Uploaded Song",
            duration: 200,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Uploader"],
            coverArtists: nil,
            userUploaded: true,
            oss: "audio/Uploaded Song (live).mp3"
        )

        let url = song.audioURL?.absoluteString
        #expect(url != nil)
        #expect(url?.hasPrefix("https://storage.neurokaraoke.com/audio/") == true)
        #expect(url?.contains("Uploaded") == true)
        #expect(url?.contains("%20") == true)
    }

    @Test("audioURL falls back to oss when absolutePath is blank")
    func songAudioURLFallsBackToOssWhenAbsolutePathIsBlank() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-blank-path",
            title: "Uploaded File",
            duration: 90,
            absolutePath: "  ",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: true,
            oss: "uploads/My Song.mp3"
        )

        #expect(
            song.audioURL?.absoluteString
                == "https://storage.neurokaraoke.com/uploads/My%20Song.mp3"
        )
    }

    @Test("audioURL preserves complete remote URLs")
    func songAudioURLPreservesRemoteURL() {
        let song = Song(
            id: "song-remote",
            title: "Remote Upload",
            duration: 90,
            absolutePath: "https://uploads.example.com/audio/My%20Song.mp3?token=abc",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: true
        )

        #expect(
            song.audioURL?.absoluteString
                == "https://uploads.example.com/audio/My%20Song.mp3?token=abc"
        )
    }

    @Test("audioURL is nil when both absolutePath and oss are nil")
    func songAudioURLNilWithoutAnyPath() {
        let song = Song(
            id: "song-nopath",
            title: "No Path",
            duration: 10,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: true
        )

        #expect(song.audioURL == nil)
    }

    @Test("Song decodes oss field from JSON")
    func songDecodesOssField() {
        useGlobalStorageRegion()
        let json = """
        {"id":"s1","title":"T","duration":5,"absolutePath":null,"oss":"audio/test.mp3","userUploaded":true}
        """.data(using: .utf8)!
        let song = try? JSONDecoder().decode(Song.self, from: json)
        #expect(song != nil)
        #expect(song?.oss == "audio/test.mp3")
        #expect(song?.audioURL?.absoluteString == "https://storage.neurokaraoke.com/audio/test.mp3")
    }

    @Test("Song decodes flexible metadata used by uploaded YouTube songs")
    func songDecodesFlexibleUploadedMetadata() throws {
        let json = """
        {
          "id": "youtube-1",
          "title": "Imported Song",
          "duration": "213.8",
          "absolutePath": "youtube/Imported Song.mp3",
          "cloudflareId": "artwork-id",
          "originalArtists": [{"name": "Original Artist"}],
          "coverArtists": "Uploader",
          "userUploaded": 1
        }
        """.data(using: .utf8)!

        let song = try JSONDecoder().decode(Song.self, from: json)

        #expect(song.duration == 213)
        #expect(song.originalArtists == ["Original Artist"])
        #expect(song.coverArtists == ["Uploader"])
        #expect(song.userUploaded == true)
        #expect(song.cloudflareID == "artwork-id")
    }

    @Test("Song uses artwork identifier nested inside coverArt")
    func songUsesNestedCoverArtworkIdentifier() throws {
        let json = """
        {
          "id": "favorite-upload",
          "title": "Uploaded Favorite",
          "duration": 180,
          "absolutePath": "uploads/favorite.m4a",
          "coverArt": {"cloudflareId": "nested-artwork-id"},
          "userUploaded": true
        }
        """.data(using: .utf8)!

        let song = try JSONDecoder().decode(Song.self, from: json)

        #expect(song.cloudflareID == nil)
        #expect(song.coverArt?.cloudflareId == "nested-artwork-id")
        #expect(song.hasOwnArtwork)
        #expect(
            song.imageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=480,quality=85,format=webp/nested-artwork-id/public"
        )
    }

    @Test("Favorite responses decode uploaded songs wrapped in an envelope")
    func favoriteEnvelopeDecodesUploadedSong() throws {
        let json = """
        {
          "items": [
            {
              "song": {
                "id": "favorite-upload",
                "title": "Uploaded Favorite",
                "duration": 123.4,
                "absolutePath": null,
                "oss": "uploads/Uploaded Favorite.mp3",
                "userUploaded": "true"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let songs = try #require(SongPayloadDecoder.decodeSongs(from: json))

        #expect(songs.map(\.id) == ["favorite-upload"])
        #expect(songs.first?.userUploaded == true)
        #expect(
            songs.first?.audioURL?.absoluteString
                == "https://storage.neurokaraoke.com/uploads/Uploaded%20Favorite.mp3"
        )
    }

    @Test("Uploaded favorites fill missing artwork from canonical song metadata")
    func uploadedFavoriteFillsMissingArtwork() throws {
        let favorite = Song(
            id: "favorite-upload",
            title: "Uploaded Favorite",
            duration: 0,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: [],
            coverArtists: nil,
            userUploaded: true,
            oss: nil
        )
        let canonical = Song(
            id: "favorite-upload",
            title: "Canonical Title",
            duration: 213,
            absolutePath: "uploads/Uploaded Favorite.m4a",
            cloudflareID: "uploaded-artwork-id",
            coverArt: Media(absolutePath: "/uploads/cover.jpg"),
            originalArtists: ["Original Artist"],
            coverArtists: ["Uploader"],
            userUploaded: true,
            oss: "uploads/fallback.m4a"
        )

        let hydrated = favorite.fillingMissingMetadata(from: canonical)

        #expect(hydrated.title == "Uploaded Favorite")
        #expect(hydrated.duration == 213)
        #expect(hydrated.absolutePath == "uploads/Uploaded Favorite.m4a")
        #expect(hydrated.cloudflareID == "uploaded-artwork-id")
        #expect(hydrated.coverArt?.absolutePath == "/uploads/cover.jpg")
        #expect(hydrated.originalArtists == ["Original Artist"])
        #expect(hydrated.coverArtists == ["Uploader"])
        #expect(hydrated.oss == "uploads/fallback.m4a")
        #expect(hydrated.hasOwnArtwork)
    }

    @Test("Favorite metadata hydrates when the upload flag is omitted")
    func favoriteMetadataHydratesWithoutUploadFlag() {
        let favorite = Song(
            id: "favorite-upload",
            title: "Uploaded Favorite",
            duration: 180,
            absolutePath: "uploads/favorite.m4a",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: nil
        )
        let canonical = Song(
            id: "favorite-upload",
            title: "Uploaded Favorite",
            duration: 180,
            absolutePath: "uploads/favorite.m4a",
            cloudflareID: nil,
            coverArt: Media(absolutePath: nil, cloudflareId: "canonical-artwork-id"),
            originalArtists: nil,
            coverArtists: ["Uploader"],
            userUploaded: true
        )

        let hydrated = favorite.fillingMissingMetadata(from: canonical)

        #expect(hydrated.userUploaded == true)
        #expect(hydrated.coverArt?.cloudflareId == "canonical-artwork-id")
        #expect(
            hydrated.rowImageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=180,quality=78,format=webp/canonical-artwork-id/public"
        )
    }

    @Test("Favorite nested artwork takes priority over canonical flat artwork")
    func favoriteNestedArtworkTakesPriority() {
        useGlobalStorageRegion()
        let favorite = Song(
            id: "favorite-upload",
            title: "Uploaded Favorite",
            duration: 180,
            absolutePath: "uploads/favorite.m4a",
            cloudflareID: nil,
            coverArt: Media(absolutePath: nil, cloudflareId: "favorite-nested-artwork-id"),
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: true
        )
        let canonical = Song(
            id: "favorite-upload",
            title: "Uploaded Favorite",
            duration: 180,
            absolutePath: "uploads/favorite.m4a",
            cloudflareID: "canonical-flat-artwork-id",
            coverArt: nil,
            originalArtists: nil,
            coverArtists: ["Uploader"],
            userUploaded: true
        )

        let hydrated = favorite.fillingMissingMetadata(from: canonical)

        #expect(hydrated.cloudflareID == nil)
        #expect(hydrated.coverArt?.cloudflareId == "favorite-nested-artwork-id")
        #expect(
            hydrated.rowImageURL?.absoluteString
                == "https://images.neurokaraoke.com/cdn-cgi/image/width=180,quality=78,format=webp/favorite-nested-artwork-id/public"
        )
    }

    @Test("Bulk song metadata request posts the song ID array")
    func bulkSongMetadataRequestPostsIDs() throws {
        let request = try KaraokeAPIClient.songsByIDsRequest(["first-id", "second-id"])
        let body = try #require(request.httpBody)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/songs/by-ids")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONDecoder().decode([String].self, from: body) == ["first-id", "second-id"])
    }

    @Test("Uploaded song metadata request uses the authenticated uploads route")
    func uploadedSongMetadataRequestUsesUploadsRoute() throws {
        let request = try KaraokeAPIClient.uploadedSongsRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/user/songs")
    }

    @Test("Uploaded song metadata cache refreshes for new favorites and after expiration")
    func uploadedSongMetadataCacheRefreshesWhenNeeded() async throws {
        let cache = UploadedSongMetadataCache(lifetime: 60)
        let loader = UploadedSongLoaderProbe()
        let start = Date(timeIntervalSince1970: 1_000)

        _ = try await cache.value(for: ["first"], at: start) { await loader.load() }
        _ = try await cache.value(for: ["first"], at: start.addingTimeInterval(30)) {
            await loader.load()
        }
        let callsForStableFavorites = await loader.callCount()

        _ = try await cache.value(
            for: ["first", "new-favorite"],
            at: start.addingTimeInterval(31)
        ) {
            await loader.load()
        }
        let callsAfterAddingFavorite = await loader.callCount()

        _ = try await cache.value(for: ["first"], at: start.addingTimeInterval(92)) {
            await loader.load()
        }
        let callsAfterExpiration = await loader.callCount()

        #expect(callsForStableFavorites == 1)
        #expect(callsAfterAddingFavorite == 2)
        #expect(callsAfterExpiration == 3)
    }

    @Test("Uploaded song metadata takes priority when hydrating favorites")
    func uploadedSongMetadataTakesPriorityForFavorites() throws {
        let favorite = Song(
            id: "favorite-upload",
            title: "Uploaded Favorite",
            duration: 180,
            absolutePath: "uploads/favorite.m4a",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: nil
        )
        let catalogVersion = Song(
            id: "favorite-upload",
            title: "Uploaded Favorite",
            duration: 180,
            absolutePath: "uploads/favorite.m4a",
            cloudflareID: "catalog-artwork-id",
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: nil
        )
        let uploadedVersion = Song(
            id: "favorite-upload",
            title: "Uploaded Favorite",
            duration: 180,
            absolutePath: "uploads/favorite.m4a",
            cloudflareID: "uploaded-artwork-id",
            coverArt: nil,
            originalArtists: nil,
            coverArtists: ["Uploader"],
            userUploaded: true
        )

        let hydrated = try #require(
            KaraokeAPIClient.hydratingFavorites(
                [favorite],
                canonicalSongs: [catalogVersion],
                uploadedSongs: [uploadedVersion]
            ).first
        )

        #expect(hydrated.cloudflareID == "uploaded-artwork-id")
        #expect(hydrated.userUploaded == true)
        #expect(hydrated.coverArtists == ["Uploader"])
    }

    @Test("Favorite metadata keeps values already supplied by favorites endpoint")
    func favoriteMetadataKeepsExistingValues() {
        let favorite = Song(
            id: "favorite-upload",
            title: "Favorite Title",
            duration: 180,
            absolutePath: "favorites/audio.m4a",
            cloudflareID: "favorite-artwork-id",
            coverArt: Media(absolutePath: "/favorites/cover.jpg"),
            originalArtists: ["Favorite Artist"],
            coverArtists: ["Favorite Uploader"],
            userUploaded: true,
            oss: "favorites/fallback.m4a"
        )
        let canonical = Song(
            id: "favorite-upload",
            title: "Canonical Title",
            duration: 213,
            absolutePath: "canonical/audio.m4a",
            cloudflareID: "canonical-artwork-id",
            coverArt: Media(absolutePath: "/canonical/cover.jpg"),
            originalArtists: ["Canonical Artist"],
            coverArtists: ["Canonical Uploader"],
            userUploaded: true,
            oss: "canonical/fallback.m4a"
        )

        let hydrated = favorite.fillingMissingMetadata(from: canonical)

        #expect(hydrated == favorite)
        #expect(hydrated.cloudflareID == "favorite-artwork-id")
        #expect(hydrated.coverArt?.absolutePath == "/favorites/cover.jpg")
        #expect(hydrated.originalArtists == ["Favorite Artist"])
    }

    @Test("Playlist detail skips malformed songs instead of failing the playlist")
    func playlistDetailSkipsMalformedSong() throws {
        let json = """
        {
          "id": "playlist-1",
          "name": "Uploads",
          "songListDTOs": [
            {
              "id": "youtube-1",
              "title": "YouTube Upload",
              "duration": "180",
              "absolutePath": "youtube/song.mp3",
              "originalArtists": [{"artistName": "Artist"}],
              "userUploaded": true
            },
            {
              "title": "Missing ID"
            }
          ]
        }
        """.data(using: .utf8)!

        let playlist = try JSONDecoder().decode(PlaylistDetail.self, from: json)

        #expect(playlist.songListDTOs.map(\.id) == ["youtube-1"])
    }

    @Test("Playlist summaries prefer the declared song count")
    func playlistSummaryPrefersDeclaredSongCount() throws {
        let json = """
        {
          "id": "playlist-count",
          "name": "Bangers",
          "songCount": 2,
          "songListDTOs": [
            {"id": "song-1", "title": "One"},
            {"id": "song-2", "title": "Two"},
            {"id": "song-3", "title": "Three"}
          ]
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(PlaylistListItem.self, from: json)

        #expect(item.asPlaylist().songCount == 2)
    }

    @Test("Playlist summaries fall back to the embedded song count")
    func playlistSummaryFallsBackToEmbeddedSongCount() throws {
        let json = """
        {
          "id": "playlist-fallback-count",
          "name": "Bangers",
          "songCount": 0,
          "songListDTOs": [
            {"id": "song-1", "title": "One"},
            {"id": "song-2", "title": "Two"}
          ]
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(PlaylistListItem.self, from: json)

        #expect(item.asPlaylist().songCount == 2)
    }

    @Test("Favourite Songs exposes a zero count")
    @MainActor
    func favoritesPlaylistExposesZeroCount() {
        let store = PlaylistSongCountStore()
        let playlist = Playlist(
            id: Playlist.favoritesID,
            name: "Favourite Songs",
            songCount: 0,
            mosaicMedia: nil,
            songListDTOs: []
        )

        #expect(store.displayedCount(for: playlist) == 0)
    }

    @Test("Favourite Songs prefers an authoritative cached count")
    @MainActor
    func favoritesPlaylistPrefersAuthoritativeCount() {
        let store = PlaylistSongCountStore()
        let playlist = Playlist(
            id: Playlist.favoritesID,
            name: "Favourite Songs",
            songCount: 73,
            mosaicMedia: nil,
            songListDTOs: nil
        )

        store.recordResolvedCount(74, for: playlist.id)

        #expect(store.displayedCount(for: playlist) == 74)
    }

    @Test("Personal playlist counts are resolved from playlist detail")
    @MainActor
    func personalPlaylistCountUsesDetail() {
        var playlist = Playlist(
            id: "personal-bangers",
            name: "Bangers",
            songCount: 498,
            mosaicMedia: nil,
            songListDTOs: nil
        )
        playlist.isPersonal = true

        #expect(PlaylistSongCountStore.needsDetailCount(for: playlist, isSaved: false))
    }

    @Test("Playlist grid hides an unverified summary count")
    @MainActor
    func playlistGridWaitsForDetailCount() {
        let store = PlaylistSongCountStore()
        var personalPlaylist = Playlist(
            id: "summary-bangers",
            name: "Bangers",
            songCount: 498,
            mosaicMedia: nil,
            songListDTOs: nil
        )
        personalPlaylist.isPersonal = true

        #expect(
            store.displayedCount(
                for: personalPlaylist,
                prefersDetailCount: true
            ) == nil
        )

        // Public playlists carry an accurate server-side count: show it
        // immediately instead of staying blank until a detail fetch.
        let publicPlaylist = Playlist(
            id: "summary-public",
            name: "Public Bangers",
            songCount: 498,
            mosaicMedia: nil,
            songListDTOs: nil
        )

        #expect(
            store.displayedCount(
                for: publicPlaylist,
                prefersDetailCount: true
            ) == 498
        )
    }

    @Test("Playlist search matches song titles and artists")
    func playlistSearchMatchesTitlesAndArtists() {
        let titleMatch = Song(
            id: "title-match",
            title: "Dancing Queen",
            duration: 210,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["ABBA"],
            coverArtists: nil,
            userUploaded: false
        )
        let artistMatch = Song(
            id: "artist-match",
            title: "As It Was",
            duration: 167,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Harry Styles"],
            coverArtists: ["Twinskaraoke"],
            userUploaded: false
        )

        #expect(
            PlaylistSongSearch.filter([titleMatch, artistMatch], matching: "dancing")
                .map(\.id) == ["title-match"]
        )
        #expect(
            PlaylistSongSearch.filter([titleMatch, artistMatch], matching: "harry")
                .map(\.id) == ["artist-match"]
        )
        #expect(
            PlaylistSongSearch.filter([titleMatch, artistMatch], matching: "twins")
                .map(\.id) == ["artist-match"]
        )
    }

    @Test("Playlist search trims its query and preserves order")
    func playlistSearchTrimsQueryAndPreservesOrder() {
        let first = Song(
            id: "first",
            title: "First Song",
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Shared Artist"],
            coverArtists: nil,
            userUploaded: false
        )
        let second = Song(
            id: "second",
            title: "Second Song",
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Shared Artist"],
            coverArtists: nil,
            userUploaded: false
        )

        #expect(
            PlaylistSongSearch.filter([first, second], matching: "  SHARED  ")
                .map(\.id) == ["first", "second"]
        )
        #expect(
            PlaylistSongSearch.filter([first, second], matching: "   ")
                .map(\.id) == ["first", "second"]
        )
    }

    @Test("Playlist search reveal requires a deliberate pull")
    func playlistSearchRevealRequiresThreshold() {
        var state = PlaylistSearchRevealState()

        let belowThreshold = state.update(
            pullDistance: PlaylistSearchRevealState.revealThreshold - 1,
            isSearchVisible: false,
            isActivelyPulling: true
        )
        let atThreshold = state.update(
            pullDistance: PlaylistSearchRevealState.revealThreshold,
            isSearchVisible: false,
            isActivelyPulling: true
        )
        let repeatedAboveThreshold = state.update(
            pullDistance: PlaylistSearchRevealState.revealThreshold + 20,
            isSearchVisible: false,
            isActivelyPulling: true
        )

        #expect(!belowThreshold)
        #expect(atThreshold)
        #expect(!repeatedAboveThreshold)
    }

    @Test("Playlist search reveal rearms after returning to rest")
    func playlistSearchRevealRearmsAfterRelease() {
        var state = PlaylistSearchRevealState()

        let initialReveal = state.update(
            pullDistance: PlaylistSearchRevealState.revealThreshold,
            isSearchVisible: false,
            isActivelyPulling: true
        )
        let release = state.update(
            pullDistance: PlaylistSearchRevealState.resetThreshold,
            isSearchVisible: false,
            isActivelyPulling: false
        )
        let secondReveal = state.update(
            pullDistance: PlaylistSearchRevealState.revealThreshold,
            isSearchVisible: false,
            isActivelyPulling: true
        )

        #expect(initialReveal)
        #expect(!release)
        #expect(secondReveal)
    }

    @Test("Playlist search reveal stays inactive while search is visible")
    func playlistSearchRevealStaysInactiveWhileVisible() {
        var state = PlaylistSearchRevealState()

        let revealWhileVisible = state.update(
            pullDistance: PlaylistSearchRevealState.revealThreshold + 40,
            isSearchVisible: true,
            isActivelyPulling: true
        )

        #expect(!revealWhileVisible)
    }

    @Test("Playlist search reveal cannot arm during ordinary scrolling")
    func playlistSearchRevealRequiresActivePulling() {
        var state = PlaylistSearchRevealState()

        let armedWhileSettling = state.update(
            pullDistance: PlaylistSearchRevealState.revealThreshold + 20,
            isSearchVisible: false,
            isActivelyPulling: false
        )

        #expect(!armedWhileSettling)
    }

    @Test("Playlist search pill hides during an intentional downward scroll")
    func playlistSearchPillAutoHideRules() {
        #expect(
            PlaylistSearchRevealState.shouldAutoHide(
                scrollOffset: PlaylistSearchRevealState.hideThreshold,
                isReady: true,
                isActivelyScrolling: true,
                isSearchModeActive: false
            )
        )
        #expect(
            !PlaylistSearchRevealState.shouldAutoHide(
                scrollOffset: PlaylistSearchRevealState.hideThreshold - 1,
                isReady: true,
                isActivelyScrolling: true,
                isSearchModeActive: false
            )
        )
        #expect(
            !PlaylistSearchRevealState.shouldAutoHide(
                scrollOffset: PlaylistSearchRevealState.hideThreshold + 20,
                isReady: false,
                isActivelyScrolling: true,
                isSearchModeActive: false
            )
        )
        #expect(
            !PlaylistSearchRevealState.shouldAutoHide(
                scrollOffset: PlaylistSearchRevealState.hideThreshold + 20,
                isReady: true,
                isActivelyScrolling: false,
                isSearchModeActive: false
            )
        )
        #expect(
            !PlaylistSearchRevealState.shouldAutoHide(
                scrollOffset: PlaylistSearchRevealState.hideThreshold + 20,
                isReady: true,
                isActivelyScrolling: true,
                isSearchModeActive: true
            )
        )
    }

    @Test("Display artist combines original and cover artists")
    func displayArtistUsesOriginalAndCoverMetadata() {
        let song = Song(
            id: "song-3",
            title: "Test Song",
            duration: 180,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Original"],
            coverArtists: ["Neuro"],
            userUploaded: false
        )

        #expect(song.displayTitle == "Test Song - Original")
        #expect(song.displayArtist == "Original · Cover by Neuro")
        #expect(song.hasArtistMetadata)
    }
}
