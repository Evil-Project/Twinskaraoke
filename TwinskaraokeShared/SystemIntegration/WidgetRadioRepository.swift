#if os(iOS)
import Foundation

nonisolated struct WidgetRadioSnapshot: Sendable, Equatable {
    var title = "Twinskaraoke Radio"
    var artist = String(localized: "Live Radio")
    var artworkFilename: String?

    static func decode(_ data: Data) -> (snapshot: Self, artworkURL: URL?) {
        var snapshot = Self()
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let now = object["now_playing"] as? [String: Any],
              let song = now["song"] as? [String: Any] else { return (snapshot, nil) }
        if let title = song["title"] as? String, !title.isEmpty { snapshot.title = title }
        else if let text = song["text"] as? String, !text.isEmpty { snapshot.title = text }
        if let artist = song["artist"] as? String, !artist.isEmpty { snapshot.artist = artist }
        let url = (song["art"] as? String).flatMap(URL.init(string:))
        return (snapshot, url?.scheme == "https" ? url : nil)
    }
}

nonisolated enum WidgetRadioRepository {
    static let refreshInterval: TimeInterval = 900
    static func fetch() async -> WidgetRadioSnapshot {
        var request = URLRequest(url: URL(string: "https://radio.twinskaraoke.com/api/nowplaying_static/neuro_21.json")!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return WidgetRadioSnapshot() }
        var result = WidgetRadioSnapshot.decode(data)
        if let url = result.artworkURL {
            let artwork = WidgetArtworkStore()
            let filename = WidgetArtworkStore.filename(for: url.absoluteString)
            if let file = artwork.url(for: filename), FileManager.default.fileExists(atPath: file.path) {
                result.snapshot.artworkFilename = filename
            } else {
                guard let original = WidgetArtworkStore.originalURL(for: url) ?? (url.host?.contains("neurokaraoke.com") == false ? url : nil) else { return result.snapshot }
                var artworkRequest = URLRequest(url: original)
                artworkRequest.timeoutInterval = 5
                if let (imageData, imageResponse) = try? await URLSession.shared.data(for: artworkRequest),
                   (imageResponse as? HTTPURLResponse)?.statusCode == 200, imageData.count <= 8_000_000 {
                    result.snapshot.artworkFilename = try? artwork.store(imageData, key: url.absoluteString)
                }
            }
        }
        return result.snapshot
    }
}
#endif
