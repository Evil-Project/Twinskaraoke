import Foundation

/// The list the iPad Home hero's Shuffle Mix row shuffles, so the row can
/// name it. Each case carries that list's songs, so the name and the songs
/// can't disagree.
enum HomeShuffleMix: Equatable {
    case madeForYou([Song])
    case trendingThisWeek([Song])

    var songs: [Song] {
        switch self {
        case let .madeForYou(songs), let .trendingThisWeek(songs): songs
        }
    }
}

extension HomeViewModel {
    /// Made for You when it has songs, otherwise the 7-day trending list. Nil
    /// when neither has songs, so the row isn't shown.
    var heroShuffleMix: HomeShuffleMix? {
        if !suggestions.isEmpty {
            return .madeForYou(suggestions)
        }
        if !trending.isEmpty {
            return .trendingThisWeek(trending)
        }
        return nil
    }
}
