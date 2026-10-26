import Foundation

extension UserProfile {
    var avatarURL: URL? {
        Self.remoteURL(from: avatarUrl)
    }

    private static func remoteURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: "\(StorageHost.base)\(ArtworkURLBuilder.normalizedPath(value))")
    }
}

extension AccountBadge {
    var iconURL: URL? {
        ArtworkURLBuilder.imageURL(
            cloudflareID: media?.cloudflareId,
            path: nil,
            variant: .thumbnail
        )
    }
}
