import SDWebImage
import SwiftUI

struct ZoomableImageViewer: View {
    let url: URL?
    let lowResURL: URL?
    @Binding var saveStatus: ArtworkSaveStatus
    let onSave: () -> Void
    var title: String?
    var subtitle: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showOverlay = true
    @State private var viewportSize: CGSize = .zero
    /// Width over height of the loaded image, once known.
    @State private var imageAspectRatio: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url {
                RemoteArtworkImage(
                    url: url, cornerRadius: 0, contentMode: .fit,
                    lowResURL: lowResURL, transparentBackground: true, fullResolution: true
                )
                .scaleEffect(scale)
                .offset(offset)
                .modifier(
                    PinchToZoomModifier(
                        scale: $scale,
                        lastScale: $lastScale,
                        offset: $offset,
                        lastOffset: $lastOffset,
                        reduceMotion: reduceMotion,
                        clampOffset: clampedOffset
                    )
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in settlePan() }
                )
                .simultaneousGesture(imageTapGesture)
            }
            if showOverlay {
                VStack {
                    // The only place two glass elements share a layer. A
                    // container renders them in one pass rather than compositing
                    // each separately; they sit at opposite edges so nothing
                    // merges visually, but the grouping is still what the
                    // effect expects.
                    GlassEffectContainer {
                        HStack {
                            GlassXButton(action: {
                                AppHaptic.dismiss.play()
                                dismiss()
                            })
                            Spacer()
                            GlassActionButton(
                                action: {
                                    AppHaptic.selection.play()
                                    onSave()
                                },
                                systemImage: saveIconName,
                                foregroundColor: saveIconColor,
                                isLoading: saveStatus == .saving,
                                accessibilityLabel: saveAccessibilityLabel
                            )
                            .disabled(saveStatus.isSaving)
                        }
                    }
                    .padding()
                    Spacer()
                    if visibleTitle != nil || visibleSubtitle != nil {
                        VStack(spacing: 4) {
                            if let title = visibleTitle {
                                Text(title)
                                    .scaledSystemFont(size: 17, weight: .bold)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            if let subtitle = visibleSubtitle {
                                Text(subtitle)
                                    .scaledSystemFont(size: 14)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea()
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        .task(id: url) { imageAspectRatio = await Self.aspectRatio(of: url) }
    }

    /// The image as `.fit` lays it out in the viewport, before zooming.
    /// Artwork is square until the real proportions are known.
    private var fittedImageSize: CGSize {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return .zero }
        let aspect = imageAspectRatio ?? 1
        return aspect >= viewportSize.width / viewportSize.height
            ? CGSize(width: viewportSize.width, height: viewportSize.width / aspect)
            : CGSize(width: viewportSize.height * aspect, height: viewportSize.height)
    }

    /// The furthest a zoomed image may sit from centre: on each axis, as far
    /// as keeps its edge at the edge of the screen, and nowhere along an axis
    /// where the zoomed image still fits. A drag can go past it while the
    /// finger is down, and springs back on release. Unbounded, a pan could
    /// leave the image entirely off screen, with nothing to grab to bring it
    /// back short of zooming out.
    ///
    /// Measured against the fitted image, not the viewport: square cover art
    /// fills a portrait screen's width but not its height, so a viewport-sized
    /// bound let a deep zoom pan the image clean off the top or bottom.
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let fitted = fittedImageSize
        let limitX = max(0, (fitted.width * scale - viewportSize.width) / 2)
        let limitY = max(0, (fitted.height * scale - viewportSize.height) / 2)
        return CGSize(
            width: min(limitX, max(-limitX, proposed.width)),
            height: min(limitY, max(-limitY, proposed.height))
        )
    }

    /// Reads the proportions from the same cache entry the viewer draws from,
    /// so it costs no second download.
    private static func aspectRatio(of url: URL?) async -> CGFloat? {
        guard let url else { return nil }
        return await withCheckedContinuation { continuation in
            var resumed = false
            SDWebImageManager.shared.loadImage(
                with: url,
                options: [],
                context: ImageCacheConfig.memoryAndDiskCacheContext,
                progress: nil
            ) { image, _, _, _, finished, _ in
                guard finished, !resumed else { return }
                resumed = true
                let size = image?.size ?? .zero
                continuation.resume(
                    returning: size.width > 0 && size.height > 0 ? size.width / size.height : nil
                )
            }
        }
    }

    private func settlePan() {
        let clamped = clampedOffset(offset, scale: scale)
        guard clamped != offset else {
            lastOffset = offset
            return
        }
        if reduceMotion {
            offset = clamped
        } else {
            withAnimation(.spring()) { offset = clamped }
        }
        lastOffset = clamped
    }

    private var imageTapGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first:
                    toggleZoom()
                case .second:
                    toggleOverlay()
                }
            }
    }

    private func toggleZoom() {
        AppHaptic.commit.play()
        let update = {
            if scale > 1 {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2
                lastScale = 2
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.spring()) {
                update()
            }
        }
    }

    private func toggleOverlay() {
        AppHaptic.selection.play()
        if reduceMotion {
            showOverlay.toggle()
        } else {
            withAnimation(AppMotion.easeInOut(duration: 0.25)) {
                showOverlay.toggle()
            }
        }
    }

    private var visibleTitle: String? {
        guard let title, !title.isEmpty else { return nil }
        return title
    }

    private var visibleSubtitle: String? {
        guard let subtitle, !subtitle.isEmpty else { return nil }
        return subtitle
    }

    private var saveIconName: String {
        switch saveStatus {
        case .success: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .saving, .idle: "square.and.arrow.down"
        }
    }

    private var saveIconColor: Color {
        switch saveStatus {
        case .success: .green
        case .failed: .orange
        case .saving: .white
        case .idle: Color.appGlassForeground
        }
    }

    private var saveAccessibilityLabel: String {
        switch saveStatus {
        case .saving:
            String(localized: "Saving image")
        case .success:
            String(localized: "Image saved")
        case .failed:
            String(localized: "Image save failed")
        case .idle:
            String(localized: "Save image")
        }
    }
}
