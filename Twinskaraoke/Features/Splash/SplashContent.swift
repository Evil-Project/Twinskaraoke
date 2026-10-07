import Foundation
import CryptoKit
import ImageIO
import UIKit

nonisolated enum SplashKind: String, Codable, CaseIterable, Identifiable {
    case install, update
    var id: String { rawValue }
}
nonisolated enum SplashLayout: String, Codable, CaseIterable { case imageAbove, textAbove, textOnly }
nonisolated enum SplashAlignment: String, Codable, CaseIterable { case leading, center, trailing }
nonisolated enum SplashBackgroundFit: String, Codable, CaseIterable { case fill, fit }
nonisolated enum SplashTypography: String, Codable, CaseIterable { case standard, large, compact }

nonisolated struct SplashSlide: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String? = "Slide title"
    var body: String? = "Description placeholder"
    var symbol: String? = "photo"
    var imageData: Data?
    var backgroundImageData: Data?
    var backgroundImageDescription: String?
    var backgroundImageFit: SplashBackgroundFit?
    var backgroundImageDim: Double?
    var imageDescription = "Image placeholder"
    var backgroundColor = "#101827"
    var textColor = "#FFFFFF"
    var layout: SplashLayout = .imageAbove
    var alignment: SplashAlignment = .center
    var typography: SplashTypography = .standard
    // Optional extensions keep original schema-1 exports readable.
    var design: SplashSlideDesign?
    var features: [SplashDemoFeature]?
    var demonstration: SplashDemonstration?
}

nonisolated struct SplashContent: Codable, Equatable {
    var schemaVersion = 1
    var kind: SplashKind
    var id: String
    var enabled = true
    var targetVersion: String?
    var targetBuild: String?
    var nextLabel = "Next"
    var finalLabel = "Done"
    var slides: [SplashSlide]

    static let maxFileBytes = 12 * 1024 * 1024
    static let maxImageBytes = 2 * 1024 * 1024
    static func placeholder(_ kind: SplashKind) -> Self {
        Self(kind: kind, id: kind == .install ? "install-placeholder" : "update-placeholder",
             enabled: kind == .install, targetVersion: kind == .update ? "1.0.14" : nil,
             slides: (0..<(kind == .install ? 3 : 2)).map { index in
                 var slide = SplashSlide(); slide.id = "\(kind.rawValue)-slide-\(index + 1)"; return slide
             })
    }

    func validate(expectedKind: SplashKind? = nil) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw SplashError(message: message) }
        }
        try require(schemaVersion == 1, "Unsupported content schema version. Expected 1.")
        try require(expectedKind == nil || kind == expectedKind, "This file is for the wrong walkthrough type.")
        try require(Self.validID(id), "Walkthrough ID must be 1–128 letters, digits, dots, underscores or hyphens.")
        try require((1...30).contains(slides.count), "A walkthrough needs 1–30 slides.")
        try require(Set(slides.map(\.id)).count == slides.count, "Slide IDs must be unique.")
        try require(!nextLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nextLabel.count <= 60, "Next label must contain 1–60 characters.")
        try require(!finalLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && finalLabel.count <= 60, "Final label must contain 1–60 characters.")
        if kind == .update {
            try require(Self.validVersion(targetVersion), "Update target version must be numeric components separated by dots.")
            if let targetBuild { try require(Self.validVersion(targetBuild), "Target build must be numeric components separated by dots, or omitted.") }
        } else {
            try require(enabled && targetVersion == nil && targetBuild == nil, "Install content must be enabled and have no release targets.")
        }
        for (index, slide) in slides.enumerated() {
            let prefix = "Slide \(index + 1): "
            try require(Self.validID(slide.id), prefix + "invalid slide ID.")
            try require((slide.title?.count ?? 0) <= 300 && (slide.body?.count ?? 0) <= 12000, prefix + "text exceeds the limit (title 300, body 12000).")
            try require(Self.validColor(slide.backgroundColor) && Self.validColor(slide.textColor), prefix + "colors must use #RRGGBB.")
            try require(slide.imageDescription.count <= 1000, prefix + "image description exceeds 1000 characters.")
            try slide.design?.validate(prefix: prefix)
            try SplashDemoFeature.validate(slide.features ?? [], prefix: prefix)
            try slide.demonstration?.validate(prefix: prefix)
            if let symbol = slide.symbol {
                try require(symbol.count <= 100 && UIImage(systemName: symbol) != nil, prefix + "unknown SF Symbol.")
            }
            try require(slide.imageData == nil || slide.symbol == nil, prefix + "choose an image or a symbol, not both.")
            if let data = slide.backgroundImageData {
                try Self.validateImage(data, description: slide.backgroundImageDescription ?? "", prefix: prefix + "background: ")
            }
            if let dim = slide.backgroundImageDim {
                try require(dim.isFinite && (0...0.9).contains(dim), prefix + "background dimming must be 0–90%.")
            }
            if let data = slide.imageData {
                try Self.validateImage(data, description: slide.imageDescription, prefix: prefix)
            }
        }
    }
    static func validateImage(_ data: Data, description: String, prefix: String) throws {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, description.count <= 1000 else {
            throw SplashError(message: prefix + "an image needs an accessibility description of 1–1000 characters.")
        }
        guard data.count <= maxImageBytes else { throw SplashError(message: prefix + "image exceeds 2 MB.") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else { throw SplashError(message: prefix + "use a valid still image up to 4096 × 4096 pixels.") }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maxFileBytes else { throw SplashError(message: "JSON exceeds 12 MB; reduce image sizes.") }
        return data
    }
    static func decode(_ data: Data, expectedKind: SplashKind? = nil) throws -> Self {
        guard data.count <= maxFileBytes else { throw SplashError(message: "JSON exceeds 12 MB.") }
        do {
            let value = try JSONDecoder().decode(Self.self, from: data)
            try value.validate(expectedKind: expectedKind); return value
        } catch let error as SplashError { throw error }
        catch let DecodingError.keyNotFound(key, context) {
            throw SplashError(message: "Missing JSON field: \((context.codingPath + [key]).map(\.stringValue).joined(separator: ".")).")
        }
        catch let DecodingError.dataCorrupted(context) {
            throw SplashError(message: "Invalid JSON at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)")
        }
        catch let DecodingError.typeMismatch(_, context) {
            throw SplashError(message: "Wrong JSON value type at \(context.codingPath.map(\.stringValue).joined(separator: ".")).")
        }
        catch { throw SplashError(message: "Invalid walkthrough JSON: \(error.localizedDescription)") }
    }
    var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    func eligible(version: String, build: String) -> Bool {
        kind == .update && enabled && targetVersion == version && (targetBuild == nil || targetBuild == build)
    }
    static func validID(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil }
    static func validColor(_ value: String) -> Bool { value.range(of: "^#[A-Fa-f0-9]{6}$", options: .regularExpression) != nil }
    static func validVersion(_ value: String?) -> Bool {
        guard let value, value.count <= 50 else { return false }
        return value.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil
    }
}

nonisolated struct SplashError: LocalizedError { let message: String; var errorDescription: String? { message } }

enum SplashBundleLoader {
    static func url(for kind: SplashKind, bundle: Bundle = .main) -> URL? {
        // Synchronized Xcode groups currently flatten JSON resources. Also support preserved folders.
        bundle.url(forResource: kind.rawValue, withExtension: "json", subdirectory: "SplashScreens")
        ?? bundle.url(forResource: kind.rawValue, withExtension: "json", subdirectory: "Resources/SplashScreens")
        ?? bundle.url(forResource: kind.rawValue, withExtension: "json")
    }
    static func load(_ kind: SplashKind, bundle: Bundle = .main) throws -> SplashContent {
        guard let url = url(for: kind, bundle: bundle) else { throw SplashError(message: "Missing bundled \(kind.rawValue).json") }
        return try SplashContent.decode(Data(contentsOf: url), expectedKind: kind)
    }
    static func runtimeContent(_ kind: SplashKind) -> SplashContent? {
        do { return try load(kind) }
        catch {
            NSLog("Splash %@: %@", kind.rawValue, error.localizedDescription)
            return kind == .install ? .placeholder(.install) : nil
        }
    }
}
