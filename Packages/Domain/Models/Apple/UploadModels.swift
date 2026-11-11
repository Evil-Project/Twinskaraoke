import Foundation

/// Optional metadata sent with an uploaded file. A blank field is left out,
/// and the server then reads that value from the file's own tags.
nonisolated struct SongUploadMetadata: Sendable, Equatable {
    var title: String
    var artist: String
    var playlistID: String?

    /// `Title`, `Artist` and `PlaylistId`, trimmed, without blank values.
    var queryItems: [URLQueryItem] {
        [("Title", title), ("Artist", artist), ("PlaylistId", playlistID ?? "")].compactMap { name, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : URLQueryItem(name: name, value: trimmed)
        }
    }
}

/// New metadata for one of the user's uploads. The edit endpoint also takes a
/// `mediaId` for cover art; the app doesn't change artwork, so it is not sent.
nonisolated struct UploadedSongEdit: Sendable, Equatable, Encodable {
    var title: String
    var artist: String
}

/// A song the server should download from a video link and add to the user's
/// uploads, optionally into a playlist.
nonisolated struct SongLinkImport: Sendable, Equatable, Encodable {
    var url: String
    var playlistID: String?

    private enum CodingKeys: String, CodingKey {
        case url
        case playlistID = "playlistId"
    }

    /// The server only downloads YouTube and Bilibili video and playlist
    /// links and rejects any other URL.
    private static let supportedHosts: Set = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be",
        "bilibili.com", "www.bilibili.com", "m.bilibili.com", "b23.tv",
    ]

    /// The link in `text` if it is an http(s) YouTube or Bilibili URL, else
    /// `nil`. Surrounding whitespace is ignored; the host must match exactly,
    /// so a supported name in a path, query or subdomain doesn't count.
    static func supportedLink(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.user == nil, components.password == nil,
              let host = components.host?.lowercased(),
              supportedHosts.contains(host)
        else { return nil }
        return components.url
    }
}

/// What an upload error response said, when it said anything readable. The
/// server's error bodies aren't specified, so parsing never fails loudly.
nonisolated struct UploadServerProblem: Sendable, Equatable {
    var message: String?
    var fieldErrors: [String: [String]]

    private static let maxPlainTextLength = 300

    /// Reads a problem-details JSON object (`title`, `detail`, `errors`) or a
    /// short plain-text body. Anything else, including an empty or malformed
    /// body, gives `nil`.
    static func parse(data: Data, contentType: String?) -> UploadServerProblem? {
        guard let mediaType = contentType?
            .split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        else { return nil }
        if mediaType == "application/json" || mediaType.hasSuffix("+json") {
            return parseJSON(data)
        }
        if mediaType == "text/plain" {
            return parsePlainText(data)
        }
        return nil
    }

    private static func parseJSON(_ data: Data) -> UploadServerProblem? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let message = [object["detail"], object["title"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        var fieldErrors: [String: [String]] = [:]
        for (field, value) in object["errors"] as? [String: Any] ?? [:] {
            let messages = (value as? [Any] ?? [value]).compactMap { $0 as? String }
            if !messages.isEmpty { fieldErrors[field] = messages }
        }
        guard message != nil || !fieldErrors.isEmpty else { return nil }
        return UploadServerProblem(message: message, fieldErrors: fieldErrors)
    }

    private static func parsePlainText(_ data: Data) -> UploadServerProblem? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !oneLine.isEmpty else { return nil }
        return UploadServerProblem(message: String(oneLine.prefix(maxPlainTextLength)), fieldErrors: [:])
    }
}

/// Why adding or changing an upload failed.
nonisolated enum SongUploadFailure: Error, Equatable {
    case signedOut
    case quotaSongs(max: Int)
    case quotaStorage(remaining: Int64, needed: Int64)
    case fileUnreadable
    case offline
    case timedOut
    case interrupted
    case server(status: Int, problem: UploadServerProblem?)
    case rateLimited(retryAfter: TimeInterval?)
    case unknown

    /// Whether trying the same request again later can succeed without the
    /// user changing anything.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .interrupted, .rateLimited:
            true
        case let .server(status, _):
            status >= 500
        case .signedOut, .quotaSongs, .quotaStorage, .fileUnreadable, .unknown:
            false
        }
    }
}

extension UploadLimits {
    /// Storage left in the user's quota; never negative.
    var remainingBytes: Int64 {
        max(0, maxStorageBytes - usedStorageBytes)
    }

    /// Songs the user can still upload; never negative.
    var remainingSongs: Int {
        max(0, maxSongs - currentSongCount)
    }

    /// The quota a file of `fileSize` bytes would exceed, song count first,
    /// or `nil` when it fits.
    func blocking(fileSize: Int64) -> SongUploadFailure? {
        if remainingSongs == 0 {
            return .quotaSongs(max: maxSongs)
        }
        if fileSize > remainingBytes {
            return .quotaStorage(remaining: remainingBytes, needed: fileSize)
        }
        return nil
    }
}
