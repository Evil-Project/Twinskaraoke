import Testing
@testable import Twinskaraoke

/// The iPad Home hero's Play Latest row plays the newest release. It used to
/// fall back to the first Made for You, New Releases or trending song, and
/// still said "Play Latest" when New Releases hadn't loaded.
@MainActor
@Suite("Home Play Latest")
struct HomePlayLatestTests {
    private static let suggestions = songs("suggestion", count: 3)
    private static let trending = songs("trending", count: 3)
    private static let releases = songs("release", count: 3)

    private static func songs(_ prefix: String, count: Int) -> [Song] {
        (1 ... count).map {
            UITestFixtures.song(id: "\(prefix)-\($0)", title: "\(prefix) \($0)", artist: "Artist")
        }
    }

    /// Fills the model as a finished load does: the newest release and its
    /// list come from the New Releases request.
    private func model(releases: [Song]) -> HomeViewModel {
        let model = HomeViewModel()
        model.suggestions = Self.suggestions
        model.trending = Self.trending
        model.newReleases = releases
        model.latestSingle = releases.first
        model.latestSingleContext = releases
        return model
    }

    @Test("Plays the newest release, with New Releases after it")
    func playsTheNewestRelease() throws {
        let latest = try #require(model(releases: Self.releases).heroLatestRelease)

        #expect(latest.song == Self.releases[0])
        #expect(latest.context == Self.releases)
    }

    @Test("No Play Latest when New Releases didn't load, even with other lists")
    func noPlayLatestWithoutReleases() {
        #expect(model(releases: []).heroLatestRelease == nil)
    }
}
