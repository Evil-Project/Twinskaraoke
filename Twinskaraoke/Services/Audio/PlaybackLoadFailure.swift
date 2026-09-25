import Foundation

/// Why the current song could not be loaded. Songs are fetched in full before
/// they play, so a dropped connection used to leave the player paused on the
/// song with nothing to say why, or that pressing play tries again.
nonisolated enum PlaybackLoadFailure: Equatable, Sendable {
    case offline
    case unavailable

    init(_ error: any Error) {
        if let urlError = error as? URLError, Self.connectivityCodes.contains(urlError.code) {
            self = .offline
        } else {
            self = .unavailable
        }
    }

    /// Failures that mean "not reachable right now" rather than "this song
    /// is broken", so the message can point at the connection.
    private static let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .internationalRoamingOff,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .timedOut,
    ]

    var message: String {
        switch self {
        case .offline: String(localized: "No Internet Connection")
        case .unavailable: String(localized: "Couldn't play this song.")
        }
    }
}
