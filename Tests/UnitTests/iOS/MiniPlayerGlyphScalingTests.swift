import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

/// The mini player's transport glyphs at an accessibility text size. Their
/// 44pt targets sit in a bar that is clipped at 48 or 58pt, so a glyph that
/// grows past its target is cut off.
@MainActor
struct MiniPlayerGlyphScalingTests {
    private static let margin: CGFloat = 20

    /// The controls drawn with a clear margin around their own frame; any
    /// opaque pixel in that margin is glyph drawn outside its target.
    private func pixelsOutsideTargets(at size: DynamicTypeSize, isPlaying: Bool, showsNext: Bool) throws -> Int {
        let controls = MiniPlayerTransportControls(isPlaying: isPlaying, isRadioMode: false, showsNext: showsNext)
            .padding(Self.margin)
            .environment(\.dynamicTypeSize, size)
        let renderer = ImageRenderer(content: controls)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let margin = Int(Self.margin)
        var count = 0
        for y in 0 ..< height {
            for x in 0 ..< width where x < margin || x >= width - margin || y < margin || y >= height - margin {
                if pixels[(y * width + x) * 4 + 3] > 16 { count += 1 }
            }
        }
        return count
    }

    @Test(arguments: [true, false])
    func glyphsStayInsideTheirTargetsAtTheLargestSize(isPlaying: Bool) throws {
        #expect(try pixelsOutsideTargets(at: .accessibility5, isPlaying: isPlaying, showsNext: true) == 0)
        #expect(try pixelsOutsideTargets(at: .accessibility5, isPlaying: isPlaying, showsNext: false) == 0)
    }

    @Test func glyphsFitAtTheDefaultSize() throws {
        #expect(try pixelsOutsideTargets(at: .large, isPlaying: false, showsNext: true) == 0)
    }
}
