import Foundation

/// What Reload repeats after a Bandle request fails.
enum BandleGameRetry: Equatable {
    /// Load today's challenge and the caller's status again.
    case reload
    /// Start the practice round again.
    case practice
    /// Load the clip for this attempt again.
    case clip(Int)
    /// Submit the same guess or skip again.
    case attempt(guess: BandleGuessSong?, isSkip: Bool)
}
