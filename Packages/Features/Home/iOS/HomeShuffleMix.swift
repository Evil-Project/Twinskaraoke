import Foundation

/// The list the iPad Home hero's Shuffle Mix row shuffles, so the row can
/// name it.
struct HomeShuffleMix: Equatable {
    enum Source: Equatable {
        case madeForYou
        case trendingThisWeek
    }

    let source: Source
    let songs: [Song]
}

extension HomeViewModel {
    /// Made for You when it has songs, otherwise the 7-day trending list. Nil
    /// when neither has songs, so the row isn't shown.
    var heroShuffleMix: HomeShuffleMix? {
        if !suggestions.isEmpty {
            return HomeShuffleMix(source: .madeForYou, songs: suggestions)
        }
        if !trending.isEmpty {
            return HomeShuffleMix(source: .trendingThisWeek, songs: trending)
        }
        return nil
    }
}
