import Foundation
import Testing
@testable import Twinskaraoke

/// Regression cover for the asset-URL derivation in `GalleryVideo`.
///
/// Each case here is a real shape observed in `/api/videos`, and three of the
/// four used to resolve to something unplayable.
@Suite("Gallery video asset URLs")
struct GalleryVideoTests {
    private static let liveHost = GalleryVideo.fallbackPullZoneHost
    private static let retiredHost = "vz-577614.b-cdn.net"

    private func makeVideo(
        absolutePath: String? = "a5f3c938-c3c4-49c0-9940-6fcd79f43e63",
        thumbnailUrl: String? = nil,
        url: String? = nil,
        songTitle: String? = nil,
        name: String = "Example",
        duration: Int? = nil,
        isWatchalong: Bool? = nil,
        category: Int? = nil
    ) -> GalleryVideo {
        GalleryVideo(
            id: "id",
            name: name,
            songId: nil,
            songTitle: songTitle,
            description: nil,
            url: url,
            thumbnailUrl: thumbnailUrl,
            absolutePath: absolutePath,
            cloudflareId: nil,
            mP4: nil,
            contentType: nil,
            videoType: nil,
            createdBy: nil,
            creatorUserId: nil,
            creatorAvatarUrl: nil,
            createdDate: nil,
            duration: duration,
            width: nil,
            height: nil,
            isWatchalong: isWatchalong,
            category: category,
            views: nil,
            upvotes: nil,
            commentCount: nil
        )
    }

    @Test("A standard thumbnail yields the master playlist beside it")
    func standardThumbnailStreamURL() {
        let video = makeVideo(
            thumbnailUrl: "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/thumbnail.jpg"
        )
        #expect(
            video.streamURL?.absoluteString
                == "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/playlist.m3u8"
        )
    }

    /// Watchalongs name their poster `thumbnail_<hash>.jpg`. The previous
    /// implementation built the stream URL by replacing the literal
    /// `/thumbnail.jpg`, which silently no-opped here and produced
    /// `…/thumbnail_270da552.jpg/playlist.m3u8` — a 404, surfacing in the app as
    /// a crossed-out play symbol.
    @Test("A hash-suffixed watchalong thumbnail still yields a valid playlist")
    func hashedThumbnailStreamURL() {
        let video = makeVideo(
            thumbnailUrl: "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/thumbnail_270da552.jpg"
        )
        #expect(
            video.streamURL?.absoluteString
                == "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/playlist.m3u8"
        )
        #expect(video.streamURL?.absoluteString.contains("thumbnail") == false)
    }

    /// 36 items in the catalogue carry no thumbnail at all. They used to fall
    /// through to the `iframe.mediadelivery.net` embed page, which AVFoundation
    /// cannot play because it is HTML.
    @Test("A missing thumbnail still yields stream and poster URLs")
    func missingThumbnailStillResolves() {
        let video = makeVideo(
            thumbnailUrl: nil,
            url: "https://iframe.mediadelivery.net/embed/577614/a5f3c938?autoplay=false"
        )
        #expect(
            video.streamURL?.absoluteString
                == "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/playlist.m3u8"
        )
        #expect(
            video.posterURL?.absoluteString
                == "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/thumbnail.jpg"
        )
    }

    /// The API still advertises a pull zone that answers 403 to everything, for
    /// roughly 1000 of ~1385 items. Both assets must be rehosted.
    @Test("A retired pull zone is rehosted for stream and poster alike")
    func retiredHostIsRehosted() {
        let video = makeVideo(
            thumbnailUrl: "https://\(Self.retiredHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/thumbnail.jpg"
        )
        #expect(video.streamURL?.host() == Self.liveHost)
        #expect(video.posterURL?.host() == Self.liveHost)
        #expect(
            video.posterURL?.absoluteString
                == "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/thumbnail.jpg"
        )
    }

    @Test("A host the API advertises is honoured when it is not retired")
    func unknownHostIsPreserved() {
        let video = makeVideo(
            thumbnailUrl: "https://vz-future-zone.b-cdn.net/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/thumbnail.jpg"
        )
        #expect(video.streamURL?.host() == "vz-future-zone.b-cdn.net")
    }

    @Test("Variant playlists address the encoder ladder directly")
    func variantStreamURLs() {
        let video = makeVideo(
            thumbnailUrl: "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/thumbnail.jpg"
        )
        #expect(
            video.variantStreamURL(for: .p720)?.absoluteString
                == "https://\(Self.liveHost)/a5f3c938-c3c4-49c0-9940-6fcd79f43e63/720p/video.m3u8"
        )
        // `auto` has no rung of its own and falls back to the master playlist.
        #expect(video.variantStreamURL(for: .auto) == video.streamURL)
    }

    @Test("Without an asset directory there is nothing to play")
    func missingAssetDirectoryYieldsNoStream() {
        let video = makeVideo(absolutePath: nil, thumbnailUrl: nil)
        #expect(video.streamURL == nil)
        #expect(video.posterURL == nil)
    }

    @Test("An absent absolutePath falls back to the thumbnail's directory")
    func thumbnailDirectoryFallback() {
        let video = makeVideo(
            absolutePath: nil,
            thumbnailUrl: "https://\(Self.liveHost)/dc0216b7-93d7-47e8-b41d-16a81037aa15/thumbnail.jpg"
        )
        #expect(
            video.streamURL?.absoluteString
                == "https://\(Self.liveHost)/dc0216b7-93d7-47e8-b41d-16a81037aa15/playlist.m3u8"
        )
    }

    @Test("Display title prefers the song title and never falls through to empty")
    func displayTitleFallback() {
        #expect(makeVideo(songTitle: "A Song", name: "Raw Name").displayTitle == "A Song")
        #expect(makeVideo(songTitle: "   ", name: "Raw Name").displayTitle == "Raw Name")
        #expect(makeVideo(songTitle: nil, name: "  ").displayTitle == "Untitled Video")
    }

    /// `duration` is absent or zero for most of the catalogue — including every
    /// long watchalong — so zero must read as "unknown", not "0:00".
    @Test("Runtime is only formatted when the API reports a usable duration")
    func runtimeFormatting() {
        #expect(makeVideo(duration: nil).formattedRuntime == nil)
        #expect(makeVideo(duration: 0).formattedRuntime == nil)
        #expect(makeVideo(duration: 45).formattedRuntime == "0:45")
        #expect(makeVideo(duration: 394).formattedRuntime == "6:34")
        #expect(makeVideo(duration: 5064).formattedRuntime == "1:24:24")
    }

    @Test("Watchalongs are recognised from either flag the API sets")
    func watchalongDetection() {
        #expect(makeVideo(isWatchalong: true).isWatchalongVideo)
        #expect(makeVideo(category: 2).isWatchalongVideo)
        #expect(!makeVideo(isWatchalong: false, category: 0).isWatchalongVideo)
        #expect(!makeVideo().isWatchalongVideo)
    }

    @Test("Quality rungs map to resolution ceilings, with auto unconstrained")
    func qualityCeilings() {
        #expect(VideoQuality.auto.maximumResolution == nil)
        #expect(VideoQuality.p1080.maximumResolution == CGSize(width: 1920, height: 1080))
        #expect(VideoQuality.p480.maximumResolution == CGSize(width: 854, height: 480))
        #expect(VideoQuality.allCases.first == .auto)
    }

    @Test("Timestamps parse with and without fractional seconds")
    func dateParsing() {
        #expect(VideoDateParser.date(from: "2026-08-06T13:33:37.4358728") != nil)
        #expect(VideoDateParser.date(from: "2026-08-06T13:33:37") != nil)
        #expect(VideoDateParser.date(from: "not a date") == nil)
    }
}
