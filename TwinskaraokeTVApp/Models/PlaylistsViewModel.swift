import Combine
import Foundation

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false
    @Published var loadError: String?

    func fetch() {
        guard !isLoading, playlists.isEmpty else { return }
        isLoading = true
        loadError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                playlists = try await KaraokeAPIClient.playlists(
                    startIndex: 0,
                    pageSize: 30,
                    isSetlist: true,
                    sortDescending: false
                )
            } catch {
                loadError = "Check your connection and try again."
            }
        }
    }
}
