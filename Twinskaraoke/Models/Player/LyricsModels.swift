import Foundation

nonisolated struct LyricLine: Identifiable, Codable {
    let id = UUID()
    let time: TimeInterval
    let text: String
    let translatedText: String?

    enum CodingKeys: String, CodingKey {
        case time
        case text
        case translatedText
    }

    init(time: TimeInterval, text: String, translatedText: String? = nil) {
        self.time = time
        self.text = text
        self.translatedText = translatedText
    }

    func withTranslation(_ translatedText: String?) -> LyricLine {
        LyricLine(time: time, text: text, translatedText: translatedText)
    }

    var isInstrumental: Bool {
        let n = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        return n.isEmpty || n == "instrumental" || n == "..." || n == "…"
            || n.contains("(instrumental)") || n.contains("[instrumental]") || n.contains("♪")
    }
}

nonisolated struct RawLyricLine: Decodable {
    let time: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case time
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .time) {
            time = value
        } else if let value = try? container.decode(Double.self, forKey: .time) {
            time = String(value)
        } else if let value = try? container.decode(Int.self, forKey: .time) {
            time = String(value)
        } else {
            time = ""
        }
        text = (try? container.decode(String.self, forKey: .text)) ?? ""
    }
}

nonisolated enum TimeSpanParser {
    static func parse(_ raw: String) -> TimeInterval? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        if let seconds = Double(normalized), seconds >= 0 {
            return seconds
        }

        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
        let parsed: TimeInterval?
        switch parts.count {
        case 2:
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else {
                return nil
            }
            parsed = minutes * 60 + seconds
        case 3:
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2])
            else {
                return nil
            }
            parsed = hours * 3600 + minutes * 60 + seconds
        default:
            parsed = nil
        }

        guard let parsed, parsed >= 0 else { return nil }
        return parsed
    }
}
