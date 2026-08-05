import Foundation

/// Tracks a view model's current "reload everything" task so its awaitable
/// pull-to-refresh entry point has something to wait on.
///
/// Collapses the stored `Task<Void, Never>?` plus `await someTask?.value` that
/// had to be added to six view models at once when their `.refreshable` closures
/// were made awaitable, and gives them the single behaviour the three view
/// models that already owned a task (`ArtistsViewModel`, `VideoGalleryViewModel`,
/// `LibrarySongsViewModel`) had arrived at by hand: cancel the superseded load,
/// clear the reference when it finishes.
///
/// Those three deliberately keep their own `activeTask`. It does more than this
/// type does — it is also cancelled from a non-isolated `deinit`, which a
/// `@MainActor` helper cannot be called from.
///
/// Cancellation is opt-in rather than automatic, because it is not uniformly
/// safe. These view models discard a superseded response with a generation or
/// request token, and `PlaylistsViewModel`'s `catch` is *not* token-guarded — it
/// clears `playlists` whenever a forced fetch fails, so cancelling its in-flight
/// request would run that path and wipe good data. Each call site therefore has
/// to opt in explicitly.
@MainActor
final class RefreshTracker {
    private var task: Task<Void, Never>?

    /// Starts tracking `task`, optionally cancelling the one it replaces.
    ///
    /// - Parameter cancellingPrevious: pass `true` only when a cancelled
    ///   request cannot corrupt state — i.e. the view model guards its response
    ///   and failure paths with a generation or request token.
    func track(_ task: Task<Void, Never>, cancellingPrevious: Bool = false) {
        if cancellingPrevious {
            self.task?.cancel()
        }
        self.task = task
    }

    /// Cancels and forgets the tracked load. Same caveat as `track`.
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Awaits the tracked load, then drops the reference so a finished task
    /// isn't held until the next one happens to replace it.
    func wait() async {
        guard let tracked = task else { return }
        await tracked.value
        // A refresh triggered while this one was in flight will have replaced
        // the reference; only clear it if it is still the task we awaited.
        if task == tracked {
            task = nil
        }
    }
}
