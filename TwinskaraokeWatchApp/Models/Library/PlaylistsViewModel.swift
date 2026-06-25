import Combine
import Foundation

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false

    func fetchMusic() {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                playlists = try await KaraokeAPIClient.playlists(
                    startIndex: 0,
                    pageSize: 15,
                    isSetlist: true,
                    sortDescending: false
                )
            } catch {
                playlists = []
            }
        }
    }
}
