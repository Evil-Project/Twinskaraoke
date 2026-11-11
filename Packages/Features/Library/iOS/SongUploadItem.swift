import Foundation

/// One upload in `SongUploadController.uploads`: a file or a link, and where
/// it is. The UI turns these values into wording.
struct SongUploadItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case file
        case link
    }

    enum Phase: Equatable {
        /// Queued behind the upload that is running.
        case waiting
        case checkingQuota
        /// Writing the upload body to disk.
        case preparing
        /// The fraction of the body sent so far.
        case uploading(Double)
        /// Sent; waiting for, or checking, the server's answer.
        case finishing
        /// The server is downloading the linked audio.
        case importing
        case succeeded(title: String)
        case failed(SongUploadFailure)

        var isFinished: Bool {
            switch self {
            case .succeeded, .failed: true
            default: false
            }
        }
    }

    let id: UUID
    /// The title the user gave, the file's name without its extension, or
    /// the link; may be empty.
    var title: String
    let kind: Kind
    var phase: Phase

    var isActive: Bool {
        !phase.isFinished
    }
}

/// An upload that has ended, for the "upload finished" message.
struct SongUploadCompletion: Equatable {
    let itemID: UUID
    let title: String
    let succeeded: Bool
}
