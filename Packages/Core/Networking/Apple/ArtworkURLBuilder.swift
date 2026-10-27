import Foundation

nonisolated enum ArtworkImageVariant {
  case row
  case thumbnail
  case card
  case hero
  case fullHD
  case blur
  case download

  var width: Int {
    switch self {
    case .row: 180
    case .thumbnail: 240
    case .card: 480
    case .hero: 960
    case .fullHD, .download: 1920
    case .blur: 32
    }
  }

  var quality: Int {
    switch self {
    case .row: 78
    case .thumbnail: 80
    case .card: 85
    case .hero: 88
    case .fullHD, .download: 90
    case .blur: 30
    }
  }

  var extraOptions: [String] {
    switch self {
    case .blur:
      ["blur=30", "format=webp"]
    default:
      ["format=webp"]
    }
  }
}

nonisolated enum ArtworkURLBuilder {
  static func imageURL(cloudflareID: String?, path: String?, variant: ArtworkImageVariant) -> URL? {
    if let cloudflareID, !cloudflareID.isEmpty {
      return cloudflareImageURL(path: cloudflareID, variant: variant)
    }
    guard let path, !path.isEmpty else { return nil }
    return cloudflareImageURL(path: path, variant: variant)
  }

  static func storageResizedURL(path: String?, variant: ArtworkImageVariant) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    return URL(string: "\(StorageHost.base)/cdn-cgi/image/\(options(for: variant))\(normalizedPath(path))")
  }

  static func variantURL(from baseURL: URL, variant: ArtworkImageVariant) -> URL? {
    guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
          let host = components.host
    else { return baseURL }

    if host.contains("images.neurokaraoke.com") {
      guard let path = cloudflareDeliveryPath(from: components.path) else { return baseURL }
      return cloudflareImageURL(path: path, variant: variant)
    } else if host.contains("storage.neurokaraoke.com") {
      guard let path = storageDeliveryPath(from: components.path) else { return baseURL }
      return storageResizedURL(path: path, variant: variant)
    } else {
      return baseURL
    }
  }

  static func normalizedPath(_ rawPath: String) -> String {
    rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
  }

  private static func options(for variant: ArtworkImageVariant) -> String {
    var parts = ["width=\(variant.width)", "quality=\(variant.quality)"]
    parts.append(contentsOf: variant.extraOptions)
    return parts.joined(separator: ",")
  }

  private static func cloudflareImageURL(path: String, variant: ArtworkImageVariant) -> URL? {
    guard let deliveryPath = cloudflareDeliveryPath(from: normalizedPath(path)) else { return nil }
    return URL(string: "\(StorageHost.images)/cdn-cgi/image/\(options(for: variant))/\(deliveryPath)")
  }

  private static func cloudflareDeliveryPath(from rawPath: String) -> String? {
    var path = normalizedPath(rawPath)
    let resizePrefix = "/cdn-cgi/image/"

    if path.hasPrefix(resizePrefix) {
      let resizedPath = path.dropFirst(resizePrefix.count)
      guard let imagePathStart = resizedPath.firstIndex(of: "/") else { return nil }
      path = String(resizedPath[imagePathStart...])
    }

    if let range = path.range(of: "/width=", options: [.backwards]) {
      path = String(path[..<range.lowerBound])
    } else if let range = path.range(of: "/quality=", options: [.backwards]) {
      path = String(path[..<range.lowerBound])
    } else if !path.hasSuffix("/public") {
      let parts = path.split(separator: "/")
      if let last = parts.last, isResizeOptionsSegment(String(last)) {
        path = "/" + parts.dropLast().joined(separator: "/")
      }
    }

    if !path.hasSuffix("/public") {
      path += "/public"
    }

    let deliveryPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return deliveryPath.isEmpty ? nil : deliveryPath
  }

  // Legacy resize URLs end in a cdn-cgi option list (e.g. "width=180,quality=78").
  // Only a trailing segment of comma-separated key=value pairs with known option
  // keys counts as resize options, so real filenames containing "=" (e.g.
  // "cover=final.jpg") are not mangled into 404s.
  private static let resizeOptionKeys: Set<String> = [
    "width", "height", "quality", "format", "fit", "blur", "dpr", "gravity",
  ]

  private static func isResizeOptionsSegment(_ segment: String) -> Bool {
    let options = segment.split(separator: ",")
    return !options.isEmpty && options.allSatisfy { option in
      // Exactly one '=' with non-empty key and value: "width=300=x.jpg" is a
      // real filename, not an option list.
      let pair = option.split(separator: "=", omittingEmptySubsequences: false)
      return pair.count == 2 && !pair[1].isEmpty && resizeOptionKeys.contains(String(pair[0]))
    }
  }

  private static func storageDeliveryPath(from rawPath: String) -> String? {
    var path = normalizedPath(rawPath)
    let resizePrefix = "/cdn-cgi/image/"

    if path.hasPrefix(resizePrefix) {
      let resizedPath = path.dropFirst(resizePrefix.count)
      guard let imagePathStart = resizedPath.firstIndex(of: "/") else { return nil }
      path = String(resizedPath[imagePathStart...])
    }

    if let range = path.range(of: "/width=", options: [.backwards]) {
      path = String(path[..<range.lowerBound])
    } else if let range = path.range(of: "/quality=", options: [.backwards]) {
      path = String(path[..<range.lowerBound])
    }

    return path == "/" ? nil : path
  }
}
