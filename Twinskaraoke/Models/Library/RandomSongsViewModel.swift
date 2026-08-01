import Foundation
import Observation

@MainActor
@Observable
final class RandomSongsViewModel {
    static let playlistID = "__random_songs__"

    private(set) var songs: [Song] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoaded = false
    private var requestToken = 0
    @ObservationIgnored private var loadTask: Task<[Song], Error>?

    var playlist: Playlist {
        Playlist(
            id: Self.playlistID,
            name: "Random Songs",
            songCount: songs.count,
            mosaicMedia: nil,
            songListDTOs: songs,
            isPersonal: true
        )
    }

    var emptyStateMessage: String {
        if let errorMessage {
            return errorMessage
        }
        return "Refresh to roll a new set of songs."
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    @discardableResult
    func reload() async -> Bool {
        requestToken += 1
        let token = requestToken
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        let task = Task { try await KaraokeAPIClient.randomSongs() }
        loadTask = task

        defer {
            if requestToken == token {
                loadTask = nil
                isLoading = false
            }
        }

        do {
            let loadedSongs = try await task.value
            guard requestToken == token else { return false }
            songs = loadedSongs
            hasLoaded = true
            errorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard requestToken == token else { return false }
            errorMessage = Self.message(for: error)
            hasLoaded = true
            return false
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let KaraokeAPIClient.APIError.httpStatus(statusCode):
            "The server returned HTTP \(statusCode)."
        case KaraokeAPIClient.APIError.decodeFailed:
            "The random songs response could not be read."
        default:
            error.localizedDescription
        }
    }
}
