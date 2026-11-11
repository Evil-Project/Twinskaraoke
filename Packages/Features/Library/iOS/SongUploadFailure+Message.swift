import Foundation

extension SongUploadFailure {
    /// What went wrong and what the user can do, in one or two sentences.
    /// The server's own message wins when it sent one.
    var userMessage: String {
        switch self {
        case .signedOut:
            String(localized: "Sign in to upload songs.")
        case let .quotaSongs(max):
            String(localized: "You've reached your limit of \(max) songs. Delete one to upload another.")
        case let .quotaStorage(remaining, needed):
            String(localized: "This file is \(Self.size(needed)), but only \(Self.size(remaining)) of your storage is left.")
        case .fileUnreadable:
            String(localized: "The file couldn't be read. Choose it again.")
        case .offline:
            String(localized: "You're offline. Connect to the internet and try again.")
        case .timedOut:
            String(localized: "The upload took too long. Try again.")
        case .interrupted:
            String(localized: "The upload was interrupted. Try again.")
        case let .server(status, problem):
            problem?.message ?? String(localized: "The server couldn't add the song (error \(status)). Try again later.")
        case .rateLimited:
            String(localized: "Too many uploads at once. Wait a moment, then try again.")
        case .unsupportedLink(.notALink):
            String(localized: "Enter a full link that starts with https://.")
        case .unsupportedLink(.discordMessageLink):
            String(localized: "This links to a Discord message. Copy the link of the attachment itself instead.")
        case .unsupportedLink(.unsupportedSite):
            String(localized: "Only YouTube, Bilibili and Discord attachment links can be imported.")
        case .unknown:
            String(localized: "Something went wrong. Try again.")
        }
    }

    /// A byte count the way Files shows it.
    nonisolated static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
