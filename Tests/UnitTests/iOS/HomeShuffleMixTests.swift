import Testing
@testable import Twinskaraoke

/// The iPad Home hero's Shuffle Mix row names the list it shuffles. Its
/// subtitle used to be a song title from Made for You, New Releases or
/// trending, while the button shuffled Made for You, or trending when signed
/// out.
@MainActor
@Suite("Home Shuffle Mix")
struct HomeShuffleMixTests {
    private static let suggestions = songs("suggestion", count: 3)
    private static let trending = songs("trending", count: 3)
    private static let releases = songs("release", count: 3)

    private static func songs(_ prefix: String, count: Int) -> [Song] {
        (1 ... count).map {
            UITestFixtures.song(id: "\(prefix)-\($0)", title: "\(prefix) \($0)", artist: "Artist")
        }
    }

    private func model(suggestions: [Song], trending: [Song], releases: [Song]) -> HomeViewModel {
        let model = HomeViewModel()
        model.suggestions = suggestions
        model.trending = trending
        model.newReleases = releases
        model.latestSingle = releases.first
        model.latestSingleContext = releases
        return model
    }

    @Test("Shuffles Made for You when it has songs")
    func shufflesMadeForYou() {
        let mix = model(suggestions: Self.suggestions, trending: Self.trending, releases: Self.releases).heroShuffleMix

        #expect(mix == HomeShuffleMix(source: .madeForYou, songs: Self.suggestions))
    }

    @Test("Shuffles Trending This Week without Made for You, as when signed out")
    func shufflesTrendingWithoutSuggestions() {
        let mix = model(suggestions: [], trending: Self.trending, releases: Self.releases).heroShuffleMix

        #expect(mix == HomeShuffleMix(source: .trendingThisWeek, songs: Self.trending))
    }

    @Test("No Shuffle Mix when neither list has songs, even with New Releases")
    func noMixWithoutEitherList() {
        let mix = model(suggestions: [], trending: [], releases: Self.releases).heroShuffleMix

        #expect(mix == nil)
    }
}
