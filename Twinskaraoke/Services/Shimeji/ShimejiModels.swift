import CoreGraphics
import Foundation
nonisolated struct ShimejiManifest: Codable, Equatable, Sendable {
    let formatVersion: Int
    let packName: String
    let characters: [ShimejiCharacterDefinition]
}

nonisolated struct ShimejiCharacterDefinition: Codable, Identifiable, Hashable, Sendable {
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

nonisolated struct ShimejiAnchor: Codable, Hashable, Sendable {
    let x: Int
    let y: Int

    var point: CGPoint { CGPoint(x: x, y: y) }
}

nonisolated struct ShimejiActionDefinition: Codable, Hashable, Sendable {
    let frames: [String]
    let frameDuration: Double
    let loop: Bool
}
nonisolated enum ShimejiActionKind: String, CaseIterable, Codable, Sendable {
    case stand
    case walk
    case fall
    case climb
    case dragged
    case sit
}
