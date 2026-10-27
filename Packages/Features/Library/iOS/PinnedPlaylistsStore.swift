import Foundation
import Observation

/// Playlists pinned to the top of Library, as Apple Music does: at most six,
/// in the order they were pinned.
///
/// Pins are kept per account rather than cleared on sign-out. An expired
/// session signs the user out on its own (`AuthManager.handleExpiredSession`),
/// and wiping the pins then would lose them to something the user never did.
/// Signing back in brings them back, and a second account on the device never
/// sees the first one's.
@MainActor
@Observable
final class PinnedPlaylistsStore {
    static let shared = PinnedPlaylistsStore(
        // UI tests start from no pins on every launch instead of inheriting
        // whatever the previous test left in the simulator's defaults.
        defaults: AppRuntime.isUITestMode ? nil : .standard,
        accountID: AuthManager.persistedUserID
    )
    static let storageKeyPrefix = "nk.pinnedPlaylists.v1"
    static let limit = 6

    private(set) var playlists: [Playlist] = []
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var accountID: String?

    init(defaults: UserDefaults?, accountID: String?) {
        self.defaults = defaults
        self.accountID = accountID
        load()
    }

    var isFull: Bool {
        playlists.count >= Self.limit
    }

    func isPinned(_ playlist: Playlist) -> Bool {
        playlists.contains { $0.id == playlist.id }
    }

    /// Appends `playlist`, so existing pins keep their places. Does nothing
    /// once six are pinned: the menu asks the user to unpin one first rather
    /// than dropping a pin they chose.
    func pin(_ playlist: Playlist) {
        guard !isPinned(playlist), !isFull else { return }
        playlists.append(Self.snapshot(of: playlist))
        save()
    }

    func unpin(_ playlist: Playlist) {
        guard isPinned(playlist) else { return }
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    /// Shows the pins that belong to `accountID`, or to the signed-out state
    /// when it is nil.
    func switchAccount(to accountID: String?) {
        guard accountID != self.accountID else { return }
        self.accountID = accountID
        playlists = []
        load()
    }

    private var storageKey: String {
        "\(Self.storageKeyPrefix).\(accountID ?? "signedOut")"
    }

    /// Metadata only. `songListDTOs` can hold a whole playlist, and a stored
    /// partial list would be worse than none: the pin's menu plays whatever
    /// songs the playlist carries. Library resolves each pin against the live
    /// playlist when it has one, so names and artwork stay current.
    private static func snapshot(of playlist: Playlist) -> Playlist {
        Playlist(
            id: playlist.id,
            name: playlist.name,
            songCount: playlist.songCount,
            media: playlist.media,
            mosaicMedia: playlist.mosaicMedia,
            songListDTOs: nil,
            isPersonal: playlist.isPersonal
        )
    }

    private func load() {
        guard let data = defaults?.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data)
        else { return }
        playlists = Array(decoded.prefix(Self.limit))
    }

    private func save() {
        guard let defaults else { return }
        if playlists.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
