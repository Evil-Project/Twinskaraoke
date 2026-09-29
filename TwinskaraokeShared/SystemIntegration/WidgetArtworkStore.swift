#if os(iOS)
import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

nonisolated struct WidgetArtworkStore: Sendable {
    let directory: URL?
    init(directory: URL? = WidgetSnapshotStore().directory) {
        self.directory = directory?.appendingPathComponent("WidgetArtwork", isDirectory: true)
    }
    /// Strip an existing resize URL back to its original delivery path.
    /// The app cache is preferred; this URL never asks Cloudflare to transform.
    static func originalURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host != nil else { return nil }
        let prefix = "/cdn-cgi/image/"
        if components.path.hasPrefix(prefix) {
            let rest = components.path.dropFirst(prefix.count)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            components.path = String(rest[slash...])
        }
        // Legacy app artwork URLs put resize options after the delivery path.
        // Avoid requesting those options when the app cache has no copy.
        for marker in ["/width=", "/quality="] {
            if let range = components.path.range(of: marker, options: .backwards) {
                components.path = String(components.path[..<range.lowerBound])
            }
        }
        return components.url
    }
    static func filename(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
    func url(for filename: String?) -> URL? {
        guard let filename, filename == URL(fileURLWithPath: filename).lastPathComponent,
              filename.hasSuffix(".jpg") else { return nil }
        return directory?.appendingPathComponent(filename)
    }
    func store(_ data: Data, key: String, limit: Int = 64) throws -> String {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 400,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let side = min(image.width, image.height)
        let squareRect = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        guard let square = image.cropping(to: squareRect) else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, square, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = Self.filename(for: key)
        try (output as Data).write(to: directory.appendingPathComponent(filename), options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        for file in files.dropFirst(max(1, limit)) { try? FileManager.default.removeItem(at: file) }
        return filename
    }
    func clear() throws {
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
#endif
