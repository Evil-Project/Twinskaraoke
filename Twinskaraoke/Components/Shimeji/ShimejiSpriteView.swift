import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Tiny in-memory cache so scrubbing through an action's frames doesn't
    /// re-read the same handful of small PNGs from disk every cycle.
    private final class ShimejiImageCache {
        static let shared = ShimejiImageCache()
        private let cache = NSCache<NSString, UIImage>()

        func image(at url: URL) -> UIImage? {
            let key = url.path as NSString
            if let cached = cache.object(forKey: key) { return cached }
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            cache.setObject(image, forKey: key)
            return image
        }
    }

    struct ShimejiSpriteView: View {
        let instance: ShimejiInstance
        private let resources = ShimejiResourceManager.shared
        @GestureState private var dragTranslation: CGSize = .zero

        private let displaySize: CGFloat = 84

        var body: some View {
            currentImage
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: displaySize, height: displaySize)
                .scaleEffect(x: instance.facingRight ? -1 : 1, y: 1)
                // instance.position tracks the sprite's feet (what the physics
                // sim rests on the floor), but .position() centers a view at
                // the given point — offset up by half the frame so the feet,
                // not the center, land on the floor surface.
                .position(x: instance.position.x, y: instance.position.y - displaySize / 2)
                .accessibilityHidden(true)
                .gesture(dragGesture)
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
    }
#endif
