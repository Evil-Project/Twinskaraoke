import Foundation

nonisolated extension Song {
  var imageURL: URL? {
    imageURL(variant: .card)
  }

  var fullHDImageURL: URL? {
    imageURL(variant: .fullHD)
  }

  var thumbnailURL: URL? {
    imageURL(variant: .thumbnail)
  }

  var rowImageURL: URL? {
    imageURL(variant: .row)
  }

  var heroImageURL: URL? {
    imageURL(variant: .hero)
  }

  var downloadCoverImageURL: URL? {
    guard hasOwnArtwork else { return nil }
    return ArtworkURLBuilder.imageURL(
      cloudflareID: artworkCloudflareID,
      path: artworkPath,
      variant: .download
    )
  }

  private func imageURL(variant: ArtworkImageVariant) -> URL? {
    ArtworkURLBuilder.imageURL(
      cloudflareID: artworkCloudflareID,
      path: artworkPath,
      variant: variant
    ) ?? neuroFallbackImageURL
  }

  private static let neuroArtistNames: Set<String> = ["Neuro", "Neuro v1", "Neuro v2"]

  private var neuroFallbackImageURL: URL? {
    #if os(watchOS) || os(tvOS) || os(macOS)
    return nil
    #else
    let artists = coverArtists ?? []
    let isNeuro = artists.contains { Self.neuroArtistNames.contains($0) }
    guard isNeuro || userUploaded == true else { return nil }
    return SongArtworkFallback.shared.art(for: id)?.url
    #endif
  }

  var fallbackArtCredit: String? {
    #if os(watchOS) || os(tvOS) || os(macOS)
    return nil
    #else
    guard !hasOwnArtwork else { return nil }
    let artists = coverArtists ?? []
    let isNeuro = artists.contains { Self.neuroArtistNames.contains($0) }
    guard isNeuro || userUploaded == true else { return nil }
    return SongArtworkFallback.shared.art(for: id)?.artistName
    #endif
  }

  var audioURL: URL? {
    for source in [absolutePath, oss].compactMap({ $0 }) {
      if let url = Self.audioURL(from: source) { return url }
    }
    return nil
  }

  private static func audioURL(from source: String) -> URL? {
    let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if value.hasPrefix("//") {
      return URL(string: "https:\(value)")
    }
    if let url = URL(string: value),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host != nil
    {
      return url
    }

    guard var components = URLComponents(string: StorageHost.base) else { return nil }
    let segments = value.split(separator: "/", omittingEmptySubsequences: true)
    guard !segments.isEmpty else { return nil }
    let encodedSegments = segments.map { segment in
      let decoded = String(segment).removingPercentEncoding ?? String(segment)
      return decoded.addingPercentEncoding(withAllowedCharacters: audioPathSegmentAllowed) ?? decoded
    }
    let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.percentEncodedPath = "/" + ([basePath] + encodedSegments)
      .filter { !$0.isEmpty }
      .joined(separator: "/")
    return components.url
  }

  private static let audioPathSegmentAllowed: CharacterSet = {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/%?#")
    return allowed
  }()
}

nonisolated extension Playlist {
  var imageURL: URL? {
    imageURL(variant: .card)
  }

  var thumbnailURL: URL? {
    imageURL(variant: .thumbnail)
  }

  var rowImageURL: URL? {
    imageURL(variant: .row)
  }

  func imageURL(variant: ArtworkImageVariant) -> URL? {
    if let url = ArtworkURLBuilder.imageURL(
      cloudflareID: media?.cloudflareId,
      path: media?.absolutePath,
      variant: variant
    ) {
      return url
    }
    if let media = mosaicMedia?.first,
      let url = ArtworkURLBuilder.imageURL(
        cloudflareID: media.cloudflareId,
        path: media.absolutePath,
        variant: variant
      )
    {
      return url
    }
    guard let song = songListDTOs?.first else { return nil }
    switch variant {
    case .row:
      return song.rowImageURL
    case .thumbnail:
      return song.thumbnailURL
    case .hero:
      return song.heroImageURL
    case .fullHD:
      return song.fullHDImageURL
    default:
      return song.imageURL
    }
  }

}

nonisolated extension SearchSongItem {
  var imageURL: URL? {
    imageURL(variant: .card)
  }

  var thumbnailURL: URL? {
    imageURL(variant: .thumbnail)
  }

  var rowImageURL: URL? {
    imageURL(variant: .row)
  }

  func imageURL(variant: ArtworkImageVariant) -> URL? {
    ArtworkURLBuilder.imageURL(
      cloudflareID: cloudflareId,
      path: coverArt?.absolutePath,
      variant: variant
    )
  }

}


nonisolated extension SearchSongItem {
  func toSong() -> Song? {
    let song = Song(
      id: id,
      title: title,
      duration: duration,
      absolutePath: absolutePath,
      cloudflareID: cloudflareId,
      coverArt: coverArt.map { SongMedia(absolutePath: $0.absolutePath) },
      originalArtists: originalArtists,
      coverArtists: coverArtists,
      userUploaded: nil,
      oss: oss
    )
    return song.audioURL != nil ? song : nil
  }
}
