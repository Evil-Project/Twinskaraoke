import Foundation

/// Optional metadata sent with an uploaded file, as multipart form fields
/// ahead of the file. A blank field is left out, and the server then reads
/// that value from the file's own tags.
nonisolated struct SongUploadMetadata: Sendable, Equatable {
    var title: String
    var artist: String
    var playlistID: String?

    /// One text part of the multipart body.
    struct FormField: Sendable, Equatable {
        var name: String
        var value: String
    }

    /// `Title`, `Artist` and `PlaylistId`, in that order, trimmed and without
    /// line breaks, which could end the part early; blank values are left out.
    var formFields: [FormField] {
        [("Title", title), ("Artist", artist), ("PlaylistId", playlistID ?? "")].compactMap { name, value in
            let oneLine = String(value.unicodeScalars.filter { $0 != "\r" && $0 != "\n" })
                .trimmingCharacters(in: .whitespaces)
            return oneLine.isEmpty ? nil : FormField(name: name, value: oneLine)
        }
    }

    /// A title for a file whose own title is blank: its name without the
    /// extension, trimmed, or `nil` when nothing is left. The server stores
    /// an upload without a title or tags with no title at all.
    static func defaultTitle(forFilename filename: String) -> String? {
        var name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = name.lastIndex(of: ".") {
            let pathExtension = name[name.index(after: dot)...]
            // "Mr. Brightside" has no extension; "song.mp3" does.
            if (1...5).contains(pathExtension.count), pathExtension.allSatisfy({ $0.isLetter || $0.isNumber }) {
                name = String(name[..<dot])
            }
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
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

    /// Why a link can't be imported.
    enum LinkProblem: Sendable, Equatable {
        /// Not an http(s) URL with a host.
        case notALink
        /// A link to a Discord message rather than to its attachment, which
        /// the server rejects.
        case discordMessageLink
        /// A URL on a site the server doesn't download from.
        case unsupportedSite
    }

    /// The server downloads YouTube and Bilibili video and playlist links and
    /// Discord attachments, and rejects any other URL.
    private static let videoHosts: Set = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be",
        "bilibili.com", "www.bilibili.com", "m.bilibili.com", "b23.tv",
    ]

    /// Discord serves attachments from these hosts, under `/attachments/`,
    /// with signed query parameters that must be kept.
    private static let discordAttachmentHosts: Set = ["cdn.discordapp.com", "media.discordapp.net"]

    /// Hosts of the Discord app, whose `/channels/` links open a message.
    private static let discordAppHosts: Set = [
        "discord.com", "www.discord.com", "ptb.discord.com", "canary.discord.com",
        "discordapp.com", "www.discordapp.com",
    ]

    /// The link in `text` if the server can import it, else `nil`: an
    /// http(s) YouTube or Bilibili URL, or an https Discord attachment URL.
    /// Surrounding whitespace is ignored; the host must match exactly, so a
    /// supported name in a path, query or subdomain doesn't count.
    static func supportedLink(_ text: String) -> URL? {
        guard case let .success(url) = classify(text) else { return nil }
        return url
    }

    /// Why `text` can't be imported, or `nil` when `supportedLink` accepts it.
    static func problem(with text: String) -> LinkProblem? {
        guard case let .failure(error) = classify(text) else { return nil }
        return error.problem
    }

    private static func classify(_ text: String) -> Result<URL, LinkProblemError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), !host.isEmpty,
              let url = components.url
        else { return .failure(LinkProblemError(.notALink)) }
        guard components.user == nil, components.password == nil else {
            return .failure(LinkProblemError(.unsupportedSite))
        }
        if videoHosts.contains(host) {
            return .success(url)
        }
        if discordAttachmentHosts.contains(host), scheme == "https", components.path.hasPrefix("/attachments/") {
            return .success(url)
        }
        if discordAppHosts.contains(host), components.path.hasPrefix("/channels/") {
            return .failure(LinkProblemError(.discordMessageLink))
        }
        return .failure(LinkProblemError(.unsupportedSite))
    }

    /// `Result` needs an `Error`; `LinkProblem` stays a plain value for the UI.
    private struct LinkProblemError: Error {
        let problem: LinkProblem
        init(_ problem: LinkProblem) { self.problem = problem }
    }
}

/// The server's answer to a link import, sent once it has downloaded the
/// audio. Every field is optional on decode, since nothing guarantees them.
nonisolated struct SongLinkImportResult: Sendable, Equatable, Decodable {
    var success: Bool
    var songID: String?
    var title: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case songID = "songId"
        case title
    }

    init(success: Bool, songID: String?, title: String?) {
        self.success = success
        self.songID = songID
        self.title = title
    }

    /// A 2xx answer without the flag still means the song was added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decodeIfPresent(Bool.self, forKey: .success)) ?? true
        songID = try? container.decodeIfPresent(String.self, forKey: .songID)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
    }

    /// The decoded answer, or `nil` for an empty body or anything that isn't
    /// a JSON object.
    static func decode(from data: Data) -> SongLinkImportResult? {
        try? JSONDecoder().decode(SongLinkImportResult.self, from: data)
    }
}

/// What an upload error response said, when it said anything readable. The
/// server's error bodies aren't specified, so parsing never fails loudly.
nonisolated struct UploadServerProblem: Sendable, Equatable {
    var message: String?
    var fieldErrors: [String: [String]]

    private static let maxPlainTextLength = 300

    /// Reads a problem-details JSON object (`title`, `detail`, `errors`), a
    /// bare JSON string (what the upload endpoints send), or a short
    /// plain-text body. Anything else, including an empty or malformed
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
        let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        if let text = json as? String {
            return oneLineProblem(text)
        }
        guard let object = json as? [String: Any] else { return nil }
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
        return oneLineProblem(text)
    }

    /// `text` on one line, with runs of whitespace collapsed, capped in length.
    private static func oneLineProblem(_ text: String) -> UploadServerProblem? {
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
    /// or `nil` when it fits. A quota the server didn't report never blocks.
    func blocking(fileSize: Int64) -> SongUploadFailure? {
        if songQuotaKnown, remainingSongs == 0 {
            return .quotaSongs(max: maxSongs)
        }
        if storageQuotaKnown, fileSize > remainingBytes {
            return .quotaStorage(remaining: remainingBytes, needed: fileSize)
        }
        return nil
    }
}
