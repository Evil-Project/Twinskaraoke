import Foundation

nonisolated struct SplashProgress: Codable, Equatable {
    var kind: SplashKind
    var id: String
    var fingerprint: String
    var index: Int
    var highestVisited: Int
}
nonisolated struct SplashState: Codable, Equatable {
    var schemaVersion = 1
    var installCompleted = false
    var completedUpdateIDs: Set<String> = []
    var pending: SplashProgress?
}

@MainActor protocol SplashStateStoring {
    /// Loads validated completion history; only a missing file represents a fresh installation.
    func read() throws -> SplashState
    func save(_ state: SplashState) throws
}

/// Main-actor confinement serializes read/modify/write transactions across all scenes.
@MainActor final class SplashStateStore: SplashStateStoring {
    let directory: URL
    var file: URL { directory.appendingPathComponent("state.json") }
    /// Uses the supplied dedicated directory for walkthrough completion history.
    init(directory: URL = SplashStateStore.defaultDirectory) { self.directory = directory }
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SplashExperience", isDirectory: true)
    }
    /// Loads validated completion history; only a missing file represents a fresh installation.
    func read() throws -> SplashState {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return SplashState()
        }
        // Permissions, protected data, corrupted JSON, and future schemas are never treated as missing.
        let state = try JSONDecoder().decode(SplashState.self, from: data)
        guard state.schemaVersion == 1,
              state.completedUpdateIDs.allSatisfy(SplashContent.validID),
              state.pending.map({ $0.index >= 0 && $0.highestVisited >= $0.index && $0.highestVisited < 30 && SplashContent.validID($0.id) && $0.fingerprint.count == 64 }) ?? true
        else { throw SplashError(message: "Walkthrough state is invalid or uses an unsupported schema. Retry when app data is available.") }
        try excludeFromBackup(directory); try excludeFromBackup(file)
        return state
    }
    /// Persists completion history atomically without including it in device backups.
    func save(_ state: SplashState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        let data = try JSONEncoder().encode(state)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try excludeFromBackup(file)
    }
    /// Marks the dedicated walkthrough resource as excluded from device backups.
    private func excludeFromBackup(_ url: URL) throws {
        var url = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
