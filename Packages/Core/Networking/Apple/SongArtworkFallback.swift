import Foundation

/// Optional artwork supplied by the app. Networking never constructs a feature service.
nonisolated final class SongArtworkFallback: @unchecked Sendable {
    struct Artwork: Sendable {
        let url: URL
        let artistName: String?
    }
    static let shared = SongArtworkFallback()
    private let lock = NSLock()
    private var provider: @Sendable (String) -> Artwork? = { _ in nil }

    func configure(_ provider: @escaping @Sendable (String) -> Artwork?) {
        lock.lock()
        self.provider = provider
        lock.unlock()
    }

    func art(for id: String) -> Artwork? {
        lock.lock()
        let provider = self.provider
        lock.unlock()
        return provider(id)
    }
}
