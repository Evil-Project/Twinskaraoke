import CoreGraphics
import Foundation

/// A rung of the Bunny Stream encoder ladder.
///
/// Every video in the gallery is published as a three-rung HLS ladder
/// (480p/720p/1080p). `auto` leaves adaptive bitrate selection to the player;
/// the fixed rungs are expressed as a *resolution ceiling* rather than a pinned
/// variant playlist, so the player can still drop below the ceiling on a poor
/// connection instead of stalling.
nonisolated enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case auto
    case p1080
    case p720
    case p480

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }

    /// Resolution ceiling, or `nil` for unconstrained adaptive selection.
    var maximumResolution: CGSize? {
        switch self {
        case .auto: nil
        case .p1080: CGSize(width: 1920, height: 1080)
        case .p720: CGSize(width: 1280, height: 720)
        case .p480: CGSize(width: 854, height: 480)
        }
    }

    /// Directory name of the matching variant playlist on the CDN.
    var variantDirectory: String? {
        switch self {
        case .auto: nil
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }
}

nonisolated struct GalleryVideo: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let songId: String?
    let songTitle: String?
    let description: String?
    let url: String?
    let thumbnailUrl: String?
    /// CDN directory holding this video's HLS ladder and poster. Present on
    /// every item in the catalogue, which is why asset URLs are built from it
    /// rather than parsed out of `thumbnailUrl`.
    let absolutePath: String?
    let cloudflareId: String?
    let mP4: String?
    let contentType: String?
    let videoType: Int?
    let createdBy: String?
    let creatorUserId: String?
    let creatorAvatarUrl: String?
    let createdDate: String?
    let duration: Int?
    let width: Int?
    let height: Int?
    let isWatchalong: Bool?
    let category: Int?
    let views: Int?
    let upvotes: Int?
    let commentCount: Int?

    // MARK: - CDN hosts

    /// Pull zone that serves the whole catalogue.
    ///
    /// Used when the API advertises no usable host of its own. Verified against
    /// a 120-item random sample plus every thumbnail-less item: both
    /// `playlist.m3u8` and `thumbnail.jpg` resolve here for all of them, and an
    /// unknown GUID 404s (so this is not a catch-all that answers 200 to
    /// anything).
    static let fallbackPullZoneHost = "vz-26de8a11-dde.b-cdn.net"

    /// Pull zones the API still advertises but which no longer serve anything.
    ///
    /// `vz-577614.b-cdn.net` answers **403 to every request** — no referer, UA
    /// or token changes that — yet it is the host named by roughly 1000 of the
    /// ~1385 `thumbnailUrl` values, all of them older uploads. Requests are
    /// rehosted onto `fallbackPullZoneHost`, preserving the path, which serves
    /// the identical objects.
    static let retiredPullZoneHosts: Set<String> = ["vz-577614.b-cdn.net"]

    // MARK: - Asset URLs

    /// Base URL of the pull zone to use for this video's assets.
    ///
    /// Prefers whatever host the API advertises so a future pull-zone rotation
    /// is picked up automatically, and only falls back to the known-good host
    /// when that one is retired or absent.
    private var cdnHost: String {
        guard let thumbnailUrl,
              let host = URLComponents(string: thumbnailUrl)?.host,
              !Self.retiredPullZoneHosts.contains(host)
        else { return Self.fallbackPullZoneHost }
        return host
    }

    /// The CDN directory for this video's assets.
    private var assetDirectory: String? {
        if let absolutePath, !absolutePath.isEmpty { return absolutePath }
        // Older items occasionally omit `absolutePath`; the thumbnail path's
        // first segment is the same directory.
        guard let thumbnailUrl,
              let path = URLComponents(string: thumbnailUrl)?.path
                  .split(separator: "/").first
        else { return nil }
        return String(path)
    }

    /// Poster image for the video.
    ///
    /// Keeps the API's own filename when it supplies one — watchalongs use a
    /// content-hashed name such as `thumbnail_270da552.jpg` rather than the
    /// usual `thumbnail.jpg` — and only rewrites the host when it is retired.
    var posterURL: URL? {
        if let thumbnailUrl, var components = URLComponents(string: thumbnailUrl),
           let host = components.host
        {
            if Self.retiredPullZoneHosts.contains(host) {
                components.host = Self.fallbackPullZoneHost
            }
            return components.url
        }
        guard let assetDirectory else { return nil }
        return URL(string: "https://\(cdnHost)/\(assetDirectory)/thumbnail.jpg")
    }

    var thumbnailURL: URL? {
        guard let baseURL = posterURL else { return nil }
        return ArtworkURLBuilder.variantURL(from: baseURL, variant: .card) ?? baseURL
    }

    var rowThumbnailURL: URL? {
        guard let baseURL = posterURL else { return nil }
        return ArtworkURLBuilder.variantURL(from: baseURL, variant: .thumbnail) ?? thumbnailURL
    }

    /// Master HLS playlist.
    ///
    /// Built from `assetDirectory`, never by editing the thumbnail filename:
    /// the previous implementation string-replaced `/thumbnail.jpg` out of
    /// `thumbnailUrl`, which silently no-opped for the hash-suffixed watchalong
    /// thumbnails and produced `…/thumbnail_270da552.jpg/playlist.m3u8` (404).
    var streamURL: URL? {
        guard let assetDirectory else { return nil }
        return URL(string: "https://\(cdnHost)/\(assetDirectory)/playlist.m3u8")
    }

    /// Variant playlist for a fixed rung of the ladder.
    ///
    /// Not used for ordinary quality selection — that applies a resolution
    /// ceiling to the master playlist instead, which keeps adaptive fallback.
    func variantStreamURL(for quality: VideoQuality) -> URL? {
        guard let assetDirectory, let directory = quality.variantDirectory else { return streamURL }
        return URL(string: "https://\(cdnHost)/\(assetDirectory)/\(directory)/video.m3u8")
    }

    /// Page on the upstream web player. Not playable by AVFoundation — it is an
    /// HTML embed — so it is only ever used for sharing.
    var embedURL: URL? {
        url.flatMap(URL.init(string:))
    }

    // MARK: - Display

    var displayTitle: String {
        let candidates = [songTitle, name].compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }
        return candidates.first ?? "Untitled Video"
    }

    var isWatchalongVideo: Bool {
        isWatchalong == true || category == 2
    }

    /// Runtime, when the API reports a usable one.
    ///
    /// The field is absent or zero for most of the catalogue (and is never set
    /// for the long watchalongs), so callers must treat `nil` as "unknown"
    /// rather than "zero length" and simply omit the badge.
    var formattedRuntime: String? {
        guard let duration, duration > 0 else { return nil }
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

nonisolated struct VideosResponse: Codable {
    let items: [GalleryVideo]
    let totalCount: Int
    let page: Int
    let pageSize: Int
}
