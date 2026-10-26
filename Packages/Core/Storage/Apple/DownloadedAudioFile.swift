import Foundation

nonisolated enum DownloadedAudioFile {
    /// Validates and files a finished download. Runs on URLSession's queue,
    /// inside the completion handler, because that is the only window in which
    /// `tempURL` still exists.
    nonisolated static func storeDownloadedAudio(
        tempURL: URL,
        destinationURL: URL
    ) -> Bool {
        guard hasValidAudioHeader(at: tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: destinationURL)
            return false
        }
    }

    nonisolated static func acceptsAudioResponse(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        guard (200 ... 299).contains(http.statusCode) else { return false }
        if http.expectedContentLength > 256 * 1024 * 1024 {
            return false
        }
        guard let mimeType = http.mimeType?.lowercased(), !mimeType.isEmpty else { return true }
        return !mimeType.hasPrefix("text/")
            && mimeType != "application/json"
            && !mimeType.hasSuffix("+json")
    }

    private nonisolated static func hasValidAudioHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 12), header.count >= 4 else { return false }
        if header[0] == 0xFF, (header[1] & 0xE0) == 0xE0 { return true }
        if header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 { return true }
        if header[0] == 0x52, header[1] == 0x49, header[2] == 0x46, header[3] == 0x46 {
            return true
        }
        if header[0] == 0x46, header[1] == 0x4F, header[2] == 0x52, header[3] == 0x4D {
            return true
        }
        if header[0] == 0x63, header[1] == 0x61, header[2] == 0x66, header[3] == 0x66 {
            return true
        }
        if header[0] == 0x66, header[1] == 0x4C, header[2] == 0x61, header[3] == 0x43 {
            return true
        }
        if header.count >= 8,
           header[4] == 0x66, header[5] == 0x74, header[6] == 0x79, header[7] == 0x70
        {
            return true
        }
        return false
    }

}
