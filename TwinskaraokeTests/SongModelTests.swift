import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Song model")
struct SongModelTests {
    private func useGlobalStorageRegion() {
        UserDefaults.standard.set("global", forKey: "nk.storageRegion")
    }

    @Test("Playlist decoding accepts empty and partially valid arrays")
    func playlistDecodingPreservesValidResponses() throws {
        let empty = try KaraokeAPIClient.decodePlaylists(from: Data("[]".utf8))
        let partial = try KaraokeAPIClient.decodePlaylists(
            from: Data(
                """
                [
                  {"id":"playlist-1","name":"Favorites","songCount":2},
                  {"unexpected":true}
                ]
                """.utf8
            )
        )

        #expect(empty.isEmpty)
        #expect(partial.map(\.id) == ["playlist-1"])
    }

    @Test("Playlist decoding rejects malformed nonempty payloads")
    func playlistDecodingRejectsMalformedPayloads() {
        let payloads = [
            "{}",
            "{\"items\":[]}",
            "[{\"unexpected\":true}]",
            "not-json",
        ]

        for payload in payloads {
            #expect(throws: KaraokeAPIClient.APIError.decodeFailed) {
                try KaraokeAPIClient.decodePlaylists(from: Data(payload.utf8))
            }
        }
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

    @Test("audioURL falls back to OSS when absolutePath is blank")
    func songAudioURLFallsBackFromBlankAbsolutePath() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-blank-path",
            title: "Uploaded Song",
            duration: 200,
            absolutePath: "  \n",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: ["Uploader"],
            coverArtists: nil,
            userUploaded: true,
            oss: "  /audio/Uploaded Song.mp3  "
        )

        #expect(
            song.audioURL?.absoluteString
                == "https://storage.neurokaraoke.com/audio/Uploaded%20Song.mp3"
        )
    }

    @Test("audioURL trims padded absolute paths")
    func songAudioURLTrimsPaddedAbsolutePath() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-padded-path",
            title: "Catalog Song",
            duration: 200,
            absolutePath: "  /songs/catalog.mp3\n",
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: false,
            oss: "audio/fallback.mp3"
        )

        #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/songs/catalog.mp3")
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

    @Test("Song init preserves oss for audioURL fallback")
    func songInitPreservesOssForAudioURL() {
        useGlobalStorageRegion()
        let song = Song(
            id: "song-oss-init",
            title: "Uploaded",
            duration: 12,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: nil,
            coverArtists: nil,
            userUploaded: true,
            oss: "audio/fallback-path.mp3"
        )
        #expect(song.oss == "audio/fallback-path.mp3")
        #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/audio/fallback-path.mp3")
    }

    @Test("Search songs decode and preserve OSS playback metadata")
    func searchSongConvertsOssOnlyResult() throws {
        useGlobalStorageRegion()
        let data = try #require(
            """
            {"id":"search-oss","title":"Uploaded","duration":42,"absolutePath":null,"oss":"audio/uploaded.mp3","userUploaded":true}
            """.data(using: .utf8)
        )
        let item = try JSONDecoder().decode(SearchSongItem.self, from: data)
        let song = try #require(item.toSong())

        #expect(item.oss == "audio/uploaded.mp3")
        #expect(item.userUploaded == true)
        #expect(song.absolutePath == nil)
        #expect(song.oss == item.oss)
        #expect(song.userUploaded == true)
        #expect(song.audioURL?.absoluteString == "https://storage.neurokaraoke.com/audio/uploaded.mp3")

        let unavailableItem = SearchSongItem(
            id: "search-unavailable",
            title: "Unavailable",
            duration: 0,
            absolutePath: " \n ",
            originalArtists: nil,
            coverArtists: nil,
            coverArt: nil,
            cloudflareId: nil,
            userUploaded: true,
            oss: "\t"
        )
        #expect(unavailableItem.toSong() == nil)
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
