import OSLog
nonisolated enum AppPerformance {
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "org.evilneuro.Twinskaraoke",
        category: "ReleasePerformance"
    )

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
