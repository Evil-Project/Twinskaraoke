import CoreGraphics
import Foundation
nonisolated enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case auto
    case p1080
    case p720
    case p480

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }
    var maximumResolution: CGSize? {
        switch self {
        case .auto: nil
        case .p1080: CGSize(width: 1920, height: 1080)
        case .p720: CGSize(width: 1280, height: 720)
        case .p480: CGSize(width: 854, height: 480)
        }
    }
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
    static let fallbackPullZoneHost = "vz-26de8a11-dde.b-cdn.net"
    static let retiredPullZoneHosts: Set<String> = ["vz-577614.b-cdn.net"]
    private var cdnHost: String {
        guard let thumbnailUrl,
              let host = URLComponents(string: thumbnailUrl)?.host,
              !Self.retiredPullZoneHosts.contains(host)
        else { return Self.fallbackPullZoneHost }
        return host
    }
    private var assetDirectory: String? {
        if let absolutePath, !absolutePath.isEmpty { return absolutePath }
        guard let thumbnailUrl,
              let path = URLComponents(string: thumbnailUrl)?.path
                  .split(separator: "/").first
        else { return nil }
        return String(path)
    }
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
    var streamURL: URL? {
        guard let assetDirectory else { return nil }
        return URL(string: "https://\(cdnHost)/\(assetDirectory)/playlist.m3u8")
    }
    func variantStreamURL(for quality: VideoQuality) -> URL? {
        guard let assetDirectory, let directory = quality.variantDirectory else { return streamURL }
        return URL(string: "https://\(cdnHost)/\(assetDirectory)/\(directory)/video.m3u8")
    }
    var embedURL: URL? {
        url.flatMap(URL.init(string:))
    }

    var displayTitle: String {
        let candidates = [songTitle, name].compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }
        return candidates.first ?? String(localized: "Untitled Video")
    }

    var isWatchalongVideo: Bool {
        isWatchalong == true || category == 2
    }
    var formattedRuntime: String? {
        guard let duration, duration > 0 else { return nil }
        return VideoTimecodeFormatter.string(fromSeconds: duration)
    }
}
nonisolated enum VideoTimecodeFormatter {
    static func string(fromSeconds totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}

nonisolated struct VideosResponse: Codable {
    let items: [GalleryVideo]
    let totalCount: Int
    let page: Int
    let pageSize: Int
}
