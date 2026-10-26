import Foundation

@MainActor
final class PlaybackSessionPersistence {
    var ready = false
    var restoreAllowed = true
    var isRestoring = false
    private var saveTask: Task<Void, Never>?
    private var lastSaveAt: TimeInterval = 0
    nonisolated static let isEnabled: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("-UITestMode") || arguments.contains("-UITestPlaybackSession")
    }()

    func schedule(periodic: Bool, save: @escaping @MainActor () -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        if periodic && now - lastSaveAt < 10 { return }
        lastSaveAt = now
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            save()
        }
    }

    isolated deinit { saveTask?.cancel() }
}
