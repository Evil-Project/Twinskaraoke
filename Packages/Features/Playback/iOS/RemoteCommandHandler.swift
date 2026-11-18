import Foundation
import MediaPlayer

/// Builds `MPRemoteCommand` target handlers that run their action on the main
/// actor.
///
/// `addTarget(handler:)` takes an un-annotated Objective-C block. A closure
/// literal written in main-actor code and passed there is inferred to be
/// main-actor isolated, so Swift checks the executor on entry and traps when
/// MediaPlayer calls it off the main thread, before any fallback inside it
/// can run. These factories are `nonisolated` and return `@Sendable`
/// closures, which carry no isolation; they hop to the main actor
/// themselves.
nonisolated enum RemoteCommandHandler {
    /// - Parameter action: Runs on the main actor; its status is returned to
    ///   MediaPlayer.
    static func make<Event>(
        _ action: @escaping @MainActor @Sendable () -> MPRemoteCommandHandlerStatus
    ) -> @Sendable (Event) -> MPRemoteCommandHandlerStatus {
        { @Sendable _ in performOnMain(action) }
    }

    /// - Parameters:
    ///   - value: Reads what the action needs from the event, on the calling
    ///     thread; returning nil fails the command without hopping.
    ///   - action: Runs on the main actor with that value.
    static func make<Event, Value: Sendable>(
        extracting value: @escaping @Sendable (Event) -> Value?,
        perform action: @escaping @MainActor @Sendable (Value) -> MPRemoteCommandHandlerStatus
    ) -> @Sendable (Event) -> MPRemoteCommandHandlerStatus {
        { @Sendable event in
            guard let value = value(event) else { return .commandFailed }
            return performOnMain { action(value) }
        }
    }

    private static func performOnMain(
        _ action: @escaping @MainActor @Sendable () -> MPRemoteCommandHandlerStatus
    ) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            // Safe: the main thread is the main actor's executor.
            return MainActor.assumeIsolated { action() }
        }
        // MediaPlayer can deliver remote-command callbacks off the main thread.
        // Return only after the playback state and Now Playing info have changed;
        // returning .success before the main actor update lets Control Center redraw
        // from stale state and can leave the play/pause button out of sync.
        // Apple documents the public integration path as MPRemoteCommandCenter
        // handlers plus MPNowPlayingInfoCenter metadata/rate updates:
        // https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MediaPlaybackGuide/Contents/Resources/en.lproj/RefiningTheUserExperience/RefiningTheUserExperience.html
        return DispatchQueue.main.sync {
            // Safe: a block run by DispatchQueue.main runs on the main thread.
            MainActor.assumeIsolated { action() }
        }
    }
}
