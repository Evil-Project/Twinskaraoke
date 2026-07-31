import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Tiny in-memory cache so scrubbing through an action's frames doesn't
    /// re-read the same handful of small PNGs from disk every cycle.
    private final class ShimejiImageCache {
        static let shared = ShimejiImageCache()
        private let cache: NSCache<NSString, UIImage>

        init() {
            cache = NSCache<NSString, UIImage>()
            cache.countLimit = 200
            cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        }

        func image(at url: URL) -> UIImage? {
            let key = url.path as NSString
            if let cached = cache.object(forKey: key) { return cached }
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            cache.setObject(image, forKey: key)
            return image
        }

        func removeAll() {
            cache.removeAllObjects()
        }
    }

    struct ShimejiSpriteView: View {
        @ObservedObject var instance: ShimejiInstance
        @ObservedObject private var resources = ShimejiResourceManager.shared
        #if os(iOS)
            @GestureState private var dragTranslation: CGSize = .zero
        #endif

        static func invalidateImageCache() {
            ShimejiImageCache.shared.removeAll()
        }

        var body: some View {
            currentImage
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: ShimejiEngine.displaySize, height: ShimejiEngine.displaySize)
                .scaleEffect(x: instance.facingRight ? -1 : 1, y: 1)
                // instance.position tracks the sprite's feet (what the physics
                // sim rests on the floor), but .position() centers a view at
                // the given point — offset up by half the frame so the feet,
                // not the center, land on the floor surface.
                .position(x: instance.position.x, y: instance.position.y - ShimejiEngine.displaySize / 2)
                .accessibilityHidden(true)
                #if os(iOS)
                    // No drag-to-throw on tvOS: the Siri Remote's focus/click
                    // model has no equivalent of dragging a fingertip across
                    // the screen, and SwiftUI's DragGesture isn't meant for
                    // that surface. They still walk, climb, and sit there —
                    // just as something to watch rather than play with.
                    .gesture(dragGesture)
                #endif
        }

        private var currentImage: Image {
            let frames = instance.currentFrames
            guard !frames.isEmpty else { return Image(systemName: "circle.fill") }
            let index = min(instance.frameIndex, frames.count - 1)
            let url = resources.imageURL(character: instance.character, frame: frames[index])
            if let uiImage = ShimejiImageCache.shared.image(at: url) {
                return Image(uiImage: uiImage)
            }
            return Image(systemName: "circle.fill")
        }

        #if os(iOS)
            private var dragGesture: some Gesture {
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if !instance.isDragHeld {
                            ShimejiEngine.shared.beginDrag(instance)
                        }
                        ShimejiEngine.shared.updateDrag(instance, to: value.location)
                    }
                    .onEnded { _ in
                        ShimejiEngine.shared.endDrag(instance)
                    }
            }
        #endif
    }
#endif
