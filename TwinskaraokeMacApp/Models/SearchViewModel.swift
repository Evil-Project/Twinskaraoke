import Foundation
import Observation

@MainActor
@Observable
final class MacSearchViewModel {
    var query = ""
    private(set) var results: [Song] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    private var queryToken = 0
    private var searchTask: Task<Void, Never>?
    private static let debounce = Duration.milliseconds(300)

    /// Debounced so typing doesn't fire a request per keystroke. Cancelling the
    /// previous task also cancels its in-flight URLSession work.
    func queryChanged() {
        searchTask?.cancel()
        queryToken &+= 1
        let token = queryToken
        isSearching = false
        errorMessage = nil
        results = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.performSearch(trimmed, token: token)
        }
    }

    private func performSearch(_ text: String, token: Int) async {
        isSearching = true
        errorMessage = nil
        defer {
            if queryToken == token { isSearching = false }
        }
        do {
            let songs = try await KaraokeAPIClient.searchSongs(query: text, pageSize: 50)
            guard !Task.isCancelled, queryToken == token else { return }
            results = songs
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, queryToken == token else { return }
            results = []
            errorMessage = "Search failed. Please try again."
        }
    }

    func clear() {
        searchTask?.cancel()
        queryToken &+= 1
        isSearching = false
        query = ""
        results = []
        errorMessage = nil
    }
}
