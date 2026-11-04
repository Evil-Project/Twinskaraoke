import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Art Gallery cache")
@MainActor
struct ArtGalleryCacheTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A catalogue in the API's shape: artist ID → number of artworks.
    private func catalog(_ artists: [(String, Int)]) -> Data {
        let json = artists.map { id, count in
            let arts = (0..<count).map { "{\"id\":\"\(id)-\($0)\"}" }.joined(separator: ",")
            return "{\"id\":\"\(id)\",\"name\":\"\(id)\",\"arts\":[\(arts)]}"
        }
        return Data("[\(json.joined(separator: ","))]".utf8)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gallery-\(UUID().uuidString)", isDirectory: true)
    }

    private func store(_ directory: URL, at date: Date) -> GalleryCatalogStore {
        GalleryCatalogStore(directory: directory, now: { date })
    }

    @Test("A second visit in the same session doesn't download again")
    func secondVisitUsesMemory() async {
        let downloads = Downloads(catalog([("a", 2)]))
        let store = store(directory(), at: start)

        let first = ArtGalleryViewModel(store: store, download: { try await downloads.next() })
        await first.load()
        let second = ArtGalleryViewModel(store: store, download: { try await downloads.next() })
        await second.load()

        #expect(second.artists.map(\.id) == ["a"])
        #expect(await downloads.requests == 1)
    }

    @Test("After a relaunch the saved catalogue shows without the network")
    func relaunchUsesDisk() async {
        let folder = directory()
        let downloads = Downloads(catalog([("a", 2)]))
        await ArtGalleryViewModel(store: store(folder, at: start), download: { try await downloads.next() }).load()

        let offline = Downloads(failing: true)
        let relaunched = ArtGalleryViewModel(store: store(folder, at: start.addingTimeInterval(60)), download: { try await offline.next() })
        await relaunched.load()

        #expect(relaunched.artists.map(\.id) == ["a"])
        #expect(!relaunched.loadFailed)
        #expect(await offline.requests == 0)
    }

    @Test("A catalogue older than 12 hours is refreshed")
    func staleCatalogueRefreshes() async {
        let folder = directory()
        let seed = Downloads(catalog([("a", 2)]))
        await ArtGalleryViewModel(store: store(folder, at: start), download: { try await seed.next() }).load()

        let downloads = Downloads(catalog([("b", 3), ("a", 2)]))
        let later = ArtGalleryViewModel(store: store(folder, at: start.addingTimeInterval(13 * 3600)), download: { try await downloads.next() })
        await later.load()

        #expect(later.artists.map(\.id) == ["b", "a"])
        #expect(await downloads.requests == 1)
    }

    @Test("Pull to refresh downloads even when the catalogue is current")
    func refreshForcesDownload() async {
        let downloads = Downloads(catalog([("a", 2)]))
        let viewModel = ArtGalleryViewModel(store: store(directory(), at: start), download: { try await downloads.next() })
        await viewModel.load()
        await viewModel.refreshGallery()

        #expect(await downloads.requests == 2)
    }

    @Test("A failed refresh keeps the saved catalogue")
    func failedRefreshKeepsCatalogue() async {
        let folder = directory()
        let seed = Downloads(catalog([("a", 2)]))
        await ArtGalleryViewModel(store: store(folder, at: start), download: { try await seed.next() }).load()

        let offline = Downloads(failing: true)
        let later = ArtGalleryViewModel(store: store(folder, at: start.addingTimeInterval(13 * 3600)), download: { try await offline.next() })
        await later.load()

        #expect(await offline.requests == 1)
        #expect(later.artists.map(\.id) == ["a"])
        #expect(!later.loadFailed)
    }

    @Test("Without a saved catalogue a failed download shows the error")
    func failureWithoutCatalogue() async {
        let seed = Downloads(failing: true)
        let viewModel = ArtGalleryViewModel(store: store(directory(), at: start), download: { try await seed.next() })
        await viewModel.load()

        #expect(viewModel.artists.isEmpty)
        #expect(viewModel.loadFailed)
    }

    @Test("Artists without artwork are left out, most artworks first")
    func filtersAndSorts() async {
        let downloads = Downloads(catalog([("few", 1), ("none", 0), ("many", 5)]))
        let viewModel = ArtGalleryViewModel(store: store(directory(), at: start), download: { try await downloads.next() })
        await viewModel.load()

        #expect(viewModel.artists.map(\.id) == ["many", "few"])
    }
}

/// Stands in for the network: counts requests and returns a fixed catalogue,
/// or fails like an offline device.
private actor Downloads {
    private(set) var requests = 0
    private let data: Data?

    init(_ data: Data) { self.data = data }
    init(failing: Bool) { data = nil }

    func next() throws -> Data {
        requests += 1
        guard let data else { throw URLError(.notConnectedToInternet) }
        return data
    }
}
