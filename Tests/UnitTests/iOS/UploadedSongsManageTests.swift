import Foundation
import Testing
@testable import Twinskaraoke

/// Editing and deleting the user's uploads against stub requests: nothing
/// reaches a server and no offline file is touched.
@MainActor
@Suite("Uploaded songs management")
struct UploadedSongsManageTests {
    @MainActor
    final class Fake {
        var songs: [Song]
        var listCalls = 0
        var updates: [(id: String, edit: UploadedSongEdit)] = []
        var updateFailure: SongUploadFailure?
        var deletes: [String] = []
        var deleteFailure: SongUploadFailure?
        var removedDownloads: [String] = []
        /// While set, a delete waits here until the test resumes it.
        var pendingDelete: CheckedContinuation<Void, Never>?
        var holdsDeletes = false
        /// Thrown by the list while set.
        var listFailure: Error?
        /// While `holdsList` is set, a list load waits here until resumed.
        var pendingList: CheckedContinuation<Void, Never>?
        var holdsList = false

        init(songs: [Song]) {
            self.songs = songs
        }

        var service: UploadedSongsViewModel.Service {
            UploadedSongsViewModel.Service(
                credential: { .available("token") },
                songs: { [self] in
                    listCalls += 1
                    if holdsList {
                        holdsList = false
                        await withCheckedContinuation { pendingList = $0 }
                    }
                    if let listFailure { throw listFailure }
                    return songs
                }
            )
        }

        var manage: UploadedSongsViewModel.ManageService {
            UploadedSongsViewModel.ManageService(
                update: { [self] id, edit in
                    updates.append((id, edit))
                    if let updateFailure { throw updateFailure }
                },
                delete: { [self] id in
                    deletes.append(id)
                    if holdsDeletes {
                        await withCheckedContinuation { pendingDelete = $0 }
                    }
                    if let deleteFailure { throw deleteFailure }
                },
                removeDownload: { [self] id in removedDownloads.append(id) }
            )
        }
    }

    private static let songs = ["a", "b", "c"].map { id in
        UITestFixtures.song(id: id, title: "Song \(id)", originalArtists: ["Artist \(id)"], coverArtists: [])
    }

    private func loaded(_ fake: Fake) async -> UploadedSongsViewModel {
        let model = UploadedSongsViewModel(service: fake.service, manage: fake.manage)
        await model.refresh()
        return model
    }

    @Test func deleteRemovesRowOptimistically() async {
        let fake = Fake(songs: Self.songs)
        fake.holdsDeletes = true
        let model = await loaded(fake)
        let task = Task { await model.delete(Self.songs[1]) }
        while fake.pendingDelete == nil { await Task.yield() }
        #expect(model.songs.map(\.id) == ["a", "c"])
        #expect(model.displayedSongs.map(\.id) == ["a", "c"])
        fake.pendingDelete?.resume()
        #expect(await task.value == nil)
        #expect(model.songs.map(\.id) == ["a", "c"])
    }

    @Test func failedDeleteRestoresRowInPlace() async {
        let fake = Fake(songs: Self.songs)
        fake.deleteFailure = .server(status: 400, problem: nil)
        let model = await loaded(fake)
        let failure = await model.delete(Self.songs[1])
        #expect(failure == .server(status: 400, problem: nil))
        #expect(model.songs.map(\.id) == ["a", "b", "c"])
        #expect(model.displayedSongs.map(\.id) == ["a", "b", "c"])
    }

    @Test func deleteRemovesOfflineCopy() async {
        let fake = Fake(songs: Self.songs)
        let model = await loaded(fake)
        _ = await model.delete(Self.songs[0])
        #expect(fake.deletes == ["a"])
        #expect(fake.removedDownloads == ["a"])
    }

    @Test func failedDeleteKeepsOfflineCopy() async {
        let fake = Fake(songs: Self.songs)
        fake.deleteFailure = .offline
        let model = await loaded(fake)
        _ = await model.delete(Self.songs[0])
        #expect(fake.removedDownloads.isEmpty)
    }

    @Test func deletedRowStaysGoneAfterAConcurrentRefresh() async {
        let fake = Fake(songs: Self.songs)
        fake.holdsDeletes = true
        let model = await loaded(fake)
        let task = Task { await model.delete(Self.songs[1]) }
        while fake.pendingDelete == nil { await Task.yield() }
        // The server still lists the song while its delete is on the way.
        await model.refresh()
        #expect(model.songs.map(\.id) == ["a", "b", "c"])
        fake.pendingDelete?.resume()
        #expect(await task.value == nil)
        #expect(model.songs.map(\.id) == ["a", "c"])
        #expect(model.displayedSongs.map(\.id) == ["a", "c"])
        #expect(fake.removedDownloads == ["b"])
    }

    @Test func loadFinishingAfterADeleteKeepsTheRowOut() async {
        let fake = Fake(songs: Self.songs)
        let model = await loaded(fake)
        fake.holdsList = true
        let reload = Task { await model.refresh() }
        while fake.pendingList == nil { await Task.yield() }
        // The delete lands while a load that started before it is on the way.
        #expect(await model.delete(Self.songs[1]) == nil)
        #expect(model.songs.map(\.id) == ["a", "c"])
        fake.pendingList?.resume()
        await reload.value
        #expect(model.songs.map(\.id) == ["a", "c"])
        #expect(model.displayedSongs.map(\.id) == ["a", "c"])
        // A later load that still lists it keeps it out too.
        await model.refresh()
        #expect(model.songs.map(\.id) == ["a", "c"])
    }

    @Test func deleteAlsoStopsAQueuedOrRunningDownload() {
        typealias Manage = UploadedSongsViewModel.ManageService
        #expect(Manage.hasOfflineWork(SongDownloadStatus(isDownloaded: true, isDownloading: false)))
        // Queued and running downloads both count as downloading.
        #expect(Manage.hasOfflineWork(SongDownloadStatus(isDownloaded: false, isDownloading: true)))
        #expect(!Manage.hasOfflineWork(SongDownloadStatus(isDownloaded: false, isDownloading: false)))
    }

    @Test func editRefreshesFromServer() async {
        let fake = Fake(songs: Self.songs)
        let model = await loaded(fake)
        let callsBefore = fake.listCalls
        fake.songs[0] = UITestFixtures.song(id: "a", title: "Renamed", originalArtists: ["Artist a"], coverArtists: [])
        let outcome = await model.update(Self.songs[0], edit: UploadedSongEdit(title: "Renamed", artist: "Artist a"))
        #expect(outcome == .saved)
        #expect(fake.listCalls == callsBefore + 1)
        #expect(model.songs.first?.title == "Renamed")
    }

    @Test func savedEditShowsEvenWhenTheReloadFails() async {
        let fake = Fake(songs: Self.songs)
        let model = await loaded(fake)
        fake.listFailure = URLError(.notConnectedToInternet)
        let outcome = await model.update(Self.songs[1], edit: UploadedSongEdit(title: " New Title", artist: "New Artist "))
        #expect(outcome == .saved)
        let row = model.songs.first { $0.id == "b" }
        #expect(row?.title == "New Title")
        #expect(row.map(UploadedSongsViewModel.artistText(for:)) == "New Artist")
        #expect(model.displayedSongs.first { $0.id == "b" }?.title == "New Title")
        #expect(model.songs.map(\.id) == ["a", "b", "c"])
    }

    @Test func editRejectsEmptyTitle() async {
        let fake = Fake(songs: Self.songs)
        let model = await loaded(fake)
        let outcome = await model.update(Self.songs[0], edit: UploadedSongEdit(title: "  \n", artist: "New"))
        #expect(outcome == .emptyTitle)
        #expect(fake.updates.isEmpty)
    }

    @Test func editTrimsWhitespace() async {
        let fake = Fake(songs: Self.songs)
        let model = await loaded(fake)
        _ = await model.update(Self.songs[0], edit: UploadedSongEdit(title: "  New Title ", artist: " Neuro, Evil  "))
        #expect(fake.updates.map(\.id) == ["a"])
        #expect(fake.updates.first?.edit == UploadedSongEdit(title: "New Title", artist: "Neuro, Evil"))
    }

    @Test func unchangedEditSendsNothing() async {
        let fake = Fake(songs: Self.songs)
        let model = await loaded(fake)
        let callsBefore = fake.listCalls
        let outcome = await model.update(Self.songs[0], edit: UploadedSongEdit(title: "Song a ", artist: " Artist a"))
        #expect(outcome == .unchanged)
        #expect(fake.updates.isEmpty)
        #expect(fake.listCalls == callsBefore)
    }

    @Test("The edit form's general message shows unless a field it shows has the server's error")
    func generalEditMessageShowsUnlessAShownFieldHasTheError() {
        typealias Model = UploadedSongsViewModel
        func server(_ fieldErrors: [String: [String]]) -> SongUploadFailure {
            .server(status: 400, problem: UploadServerProblem(message: "Could not save.", fieldErrors: fieldErrors))
        }
        #expect(Model.generalEditMessage(for: nil) == nil)
        #expect(Model.generalEditMessage(for: .offline) == SongUploadFailure.offline.userMessage)
        #expect(Model.generalEditMessage(for: server([:])) == "Could not save.")
        // A field the form doesn't show: only the general message tells.
        #expect(Model.generalEditMessage(for: server(["Genre": ["Bad."]])) == "Could not save.")
        #expect(Model.generalEditMessage(for: server(["title": ["Taken."]])) == nil)
        #expect(Model.generalEditMessage(for: server(["Artist": ["Too long."], "Genre": ["Bad."]])) == nil)
    }

    @Test func failedEditKeepsTheServerProblem() async {
        let fake = Fake(songs: Self.songs)
        let problem = UploadServerProblem(message: nil, fieldErrors: ["title": ["Too long."]])
        fake.updateFailure = .server(status: 400, problem: problem)
        let model = await loaded(fake)
        let outcome = await model.update(Self.songs[0], edit: UploadedSongEdit(title: "X", artist: ""))
        #expect(outcome == .failed(.server(status: 400, problem: problem)))
        #expect(model.songs.first?.title == "Song a")
    }
}
