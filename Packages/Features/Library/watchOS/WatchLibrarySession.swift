import Foundation

@MainActor
protocol WatchLibrarySession: AnyObject {
    var accountRevision: Int { get }
    func fetchPersonalPlaylists() async throws -> [Playlist]?
}

/// Bound by the companion adapter at activation; models remain independently testable.
@MainActor
enum WatchLibraryServices {
    static weak var session: (any WatchLibrarySession)?
    static func personalPlaylists() async throws -> [Playlist]? {
        try await session?.fetchPersonalPlaylists()
    }
}
