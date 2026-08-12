import Foundation

enum LyricsTranslationError: Error {
    case unavailable
    case invalidResponse
}

final class LyricsTranslationService {
    static let shared = LyricsTranslationService()

    private let defaults = UserDefaults.standard
    private let endpointKey = "nk.lyricsTranslationEndpoint"
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0

    private init() {}

    var isConfigured: Bool {
        endpointURL != nil
    }

    func translate(songID: String, lyrics: [LyricLine]) async throws -> [LyricLine] {
        guard let endpointURL else { throw LyricsTranslationError.unavailable }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if Self.isFirstPartyEndpoint(endpointURL) {
            if let token = CredentialStore.token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            GuestIdentity.applyIfNeeded(to: &request)
        }
        request.httpBody = try JSONEncoder().encode(TranslationRequest(songID: songID, lyrics: lyrics))

        var lastError: Error?
        for attempt in 0 ..< maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw LyricsTranslationError.invalidResponse
                }

                if (200 ..< 300).contains(http.statusCode) {
                    let translatedLines = try decodeTranslations(from: data)
                    guard translatedLines.count == lyrics.count else {
                        throw LyricsTranslationError.invalidResponse
                    }

                    return zip(lyrics, translatedLines).map { line, translatedText in
                        line.withTranslation(translatedText)
                    }
                }

                if http.statusCode >= 500 || http.statusCode == 429 {
                    lastError = LyricsTranslationError.invalidResponse
                    if attempt < maxRetries - 1 {
                        let delay = baseDelay * pow(2.0, Double(attempt))
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                }

                throw LyricsTranslationError.invalidResponse
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                lastError = error
                if shouldRetry(urlError: error), attempt < maxRetries - 1 {
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }

        throw lastError ?? LyricsTranslationError.invalidResponse
    }

    static func isFirstPartyEndpoint(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              url.port == nil || url.port == 443
        else {
            return false
        }
        return host == "api.neurokaraoke.com" || host == "api.neurokaraoke.com.cn"
    }

    private var endpointURL: URL? {
        guard let raw = defaults.string(forKey: endpointKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        return URL(string: raw)
    }

    private func decodeTranslations(from data: Data) throws -> [String] {
        if let direct = try? JSONDecoder().decode([String].self, from: data) {
            return direct
        }
        if let wrapped = try? JSONDecoder().decode(TranslationResponse.self, from: data) {
            if !wrapped.lines.isEmpty {
                return wrapped.lines.map(\.text)
            }
            if !wrapped.translations.isEmpty {
                return wrapped.translations
            }
            if !wrapped.items.isEmpty {
                return wrapped.items.map(\.text)
            }
        }
        throw LyricsTranslationError.invalidResponse
    }

    private func shouldRetry(urlError: URLError) -> Bool {
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
            true
        default:
            false
        }
    }
}

private struct TranslationRequest: Encodable {
    let songID: String
    let lyrics: [TranslationRequestLine]

    init(songID: String, lyrics: [LyricLine]) {
        self.songID = songID
        self.lyrics = lyrics.map { TranslationRequestLine(time: $0.time, text: $0.text) }
    }
}

private struct TranslationRequestLine: Encodable {
    let time: TimeInterval
    let text: String
}

private struct TranslationResponse: Decodable {
    let lines: [TranslationResponseLine]
    let translations: [String]
    let items: [TranslationResponseLine]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = (try? container.decode([TranslationResponseLine].self, forKey: .lines)) ?? []
        translations = (try? container.decode([String].self, forKey: .translations)) ?? []
        items = (try? container.decode([TranslationResponseLine].self, forKey: .items)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case lines
        case translations
        case items
    }
}

private struct TranslationResponseLine: Decodable {
    let text: String
}
