import Foundation
import Observation

nonisolated struct FallbackArt {
    let url: URL
    let artistName: String?
    let artistLink: String?
}

/// Main-actor change signal for `FallbackArtProvider`.
///
/// The provider itself stays non-observable: it is `nonisolated`, mutates its
/// pool under an `NSLock` from background URLSession callbacks, and
/// `@Observable` gives no thread safety for that. It used to broadcast through
/// `objectWillChange.send()`; observers now watch this counter instead, which
/// is only ever bumped on the main actor.
@MainActor
@Observable
final class FallbackArtRevision {
    static let shared = FallbackArtRevision()

    private(set) var revision: UInt64 = 0

    private init() {}

    /// Callable from the provider's background URLSession callbacks; the
    /// counter itself is only ever written on the main actor.
    nonisolated static func bump() {
        Task { @MainActor in
            shared.revision &+= 1
        }
    }
}

final nonisolated class FallbackArtProvider: @unchecked Sendable {
    static let shared = FallbackArtProvider()

    private var items: [FallbackArtItem] = []
    private let lock = NSLock()
    private let legacyBindingsKey = "nk.fallbackArtCache"
    private let persistedPoolKey = "nk.fallbackArtPool"
    private let session: URLSession
    private let targetPoolSize = 12

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: configuration)
        loadPersistedPool()
        UserDefaults.standard.removeObject(forKey: legacyBindingsKey)
        fetch()
    }

    func art(for id: String) -> FallbackArt? {
        lock.lock()
        defer { lock.unlock() }

        guard !items.isEmpty else { return nil }
        let item = items[Self.fallbackIndex(for: id, count: items.count)]
        return FallbackArt(url: item.url, artistName: item.artistName, artistLink: item.artistLink)
    }

    func url(for id: String) -> URL? {
        art(for: id)?.url
    }

    func resetBindings() {
        UserDefaults.standard.removeObject(forKey: legacyBindingsKey)
    }

    var randomURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        if !items.isEmpty {
            return items[Int.random(in: 0 ..< items.count)].url
        }

        return nil
    }

    private static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return Int(hash % UInt64(Int.max))
    }

    nonisolated static func fallbackIndex(for id: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return stableHash(id) % count
    }

    private func loadPersistedPool() {
        guard let data = UserDefaults.standard.data(forKey: persistedPoolKey),
              let persistedItems = try? JSONDecoder().decode([FallbackArtItem].self, from: data)
        else { return }
        items = Array(persistedItems.prefix(targetPoolSize))
    }

    private func persistPool(_ pool: [FallbackArtItem]) {
        guard let data = try? JSONEncoder().encode(Array(pool.prefix(targetPoolSize))) else { return }
        UserDefaults.standard.set(data, forKey: persistedPoolKey)
    }

    // Collects results from concurrent fetch callbacks; guarded by syncQueue.
    private final class ItemCollector: @unchecked Sendable {
        var items: [FallbackArtItem] = []
    }

    private func fetch() {
        let fetchCount = max(0, targetPoolSize - items.count)
        guard fetchCount > 0 else { return }
        let fetchedItems = ItemCollector()
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "com.twinskaraoke.fallbackart.sync")

        for _ in 0 ..< fetchCount {
            group.enter()
            let urlString = "\(StorageHost.api)/public/art/yuri/random"
            guard let url = URL(string: urlString) else {
                group.leave()
                continue
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            GuestIdentity.applyIfNeeded(to: &request)

            retryDataTask(with: request, maxAttempts: 2) { data, response, error in
                defer { group.leave() }
                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      (200 ... 299).contains(httpResponse.statusCode),
                      let data,
                      let item = try? JSONDecoder().decode(RandomArtItem.self, from: data),
                      let baseURL = URL(string: item.url)
                else { return }

                let urlWithQuality =
                    ArtworkURLBuilder.variantURL(from: baseURL, variant: .card)
                    ?? URL(string: "\(item.url)/width=480,quality=85,format=webp")
                    ?? baseURL

                let fallbackItem = FallbackArtItem(
                    url: urlWithQuality,
                    artistName: item.artistCredit,
                    artistLink: nil
                )
                syncQueue.sync {
                    fetchedItems.items.append(fallbackItem)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            lock.lock()
            let uniqueItems = (items + fetchedItems.items).reduce(into: [FallbackArtItem]()) { result, item in
                guard !result.contains(where: { $0.url == item.url }) else { return }
                result.append(item)
            }
            items = Array(uniqueItems.prefix(targetPoolSize))
            let updatedPool = items
            lock.unlock()
            persistPool(updatedPool)
            UserDefaults.standard.removeObject(forKey: legacyBindingsKey)

            FallbackArtRevision.bump()
        }
    }

    private func retryDataTask(
        with request: URLRequest,
        maxAttempts: Int,
        attempt: Int = 1,
        completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) {
        session.dataTask(with: request) { data, response, error in
            let shouldRetry = error != nil || (response as? HTTPURLResponse).map { !((200 ... 299).contains($0.statusCode)) } ?? true

            if shouldRetry, attempt < maxAttempts {
                let delay = min(pow(2.0, Double(attempt - 1)), 4.0)
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.retryDataTask(with: request, maxAttempts: maxAttempts, attempt: attempt + 1, completion: completion)
                }
            } else {
                completion(data, response, error)
            }
        }.resume()
    }

}

private nonisolated struct FallbackArtItem: Codable {
    let url: URL
    let artistName: String?
    let artistLink: String?
}

private nonisolated struct RandomArtItem: Decodable {
    let url: String
    let artistCredit: String?
}
