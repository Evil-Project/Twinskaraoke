import CoreGraphics
import Foundation

/// Matches the `manifest.json` at the root of the downloaded Shimeji
/// resource pack (shimeji_nwero.zip). Kept intentionally simple — one
/// manifest describes every character, and every character exposes the
/// same fixed set of action names our engine understands. Adding a new
/// character or a richer per-character asset set never requires an app
/// update, only a new zip.
struct ShimejiManifest: Codable, Equatable {
    let formatVersion: Int
    let packName: String
    let characters: [ShimejiCharacterDefinition]
}

struct ShimejiCharacterDefinition: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let folder: String
    let frameSize: Int
    let anchor: ShimejiAnchor
    let actions: [String: ShimejiActionDefinition]

    func action(_ kind: ShimejiActionKind) -> ShimejiActionDefinition? {
        actions[kind.rawValue]
    }
}

struct ShimejiAnchor: Codable, Hashable {
    let x: Int
    let y: Int

    var point: CGPoint { CGPoint(x: x, y: y) }
}

struct ShimejiActionDefinition: Codable, Hashable {
    let frames: [String]
    let frameDuration: Double
    let loop: Bool
}

/// The action names our engine drives directly. These map 1:1 onto keys in
/// each character's `actions` dictionary in manifest.json. A character that
/// is missing an optional action (e.g. no dedicated "sit" pose) simply falls
/// back to "stand" at runtime — see ShimejiInstance.frames(for:).
enum ShimejiActionKind: String, CaseIterable, Codable {
    case stand
    case walk
    case fall
    case climb
    case dragged
    case sit
}
