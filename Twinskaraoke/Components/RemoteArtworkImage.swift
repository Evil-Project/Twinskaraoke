import SDWebImageSwiftUI
import SwiftUI

enum ImageCacheConfig {
    private static var didApply = false
    static func applyLimits() {
        guard !didApply else { return }
        didApply = true
        let cfg = SDImageCache.shared.config
        cfg.maxMemoryCost = 64 * 1024 * 1024
        cfg.maxMemoryCount = 96
        cfg.maxDiskSize = 256 * 1024 * 1024
        cfg.shouldCacheImagesInMemory = true
        cfg.shouldUseWeakMemoryCache = true
        cfg.maxDiskAge = 30 * 24 * 60 * 60
        SDImageCache.shared.clearMemory()
        let dl = SDWebImageDownloader.shared

        dl.config.maxConcurrentDownloads = 4
        dl.requestModifier = SDWebImageDownloaderRequestModifier { request in
            var r = request
            r.cachePolicy = .returnCacheDataElseLoad
            r.timeoutInterval = 15
            return r
        }
        #if canImport(UIKit)
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil, queue: .main
            ) { _ in
                SDImageCache.shared.clearMemory()
            }
        #endif
    }

    static let thumbnailPixelSize = CGSize(width: 480, height: 480)

    static let defaultOptions: SDWebImageOptions = [
        .retryFailed,
        .scaleDownLargeImages,
    ]
}

struct RemoteArtworkImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var contentMode: ContentMode = .fill
    var showsLoading: Bool = true
    var lowResURL: URL?
    var transparentBackground: Bool = false
    var fullResolution: Bool = false

    var fixedDisplaySize: CGSize?
    @State private var fullLoaded: Bool = false
    @State private var loadFailed: Bool = false
    @State private var renderedFullURL: URL?
    var body: some View {
        Group {
            if let fixedDisplaySize {
                imageContent(size: fixedDisplaySize)
                    .frame(width: fixedDisplaySize.width, height: fixedDisplaySize.height)
            } else {
                GeometryReader { geo in
                    imageContent(size: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: url) {
            fullLoaded = false
            loadFailed = false
            renderedFullURL = nil
        }
    }

    @ViewBuilder
    private func imageContent(size: CGSize) -> some View {
        let displaySize = sanitizedDisplaySize(size)
        let pixelSize = NSValue(cgSize: thumbnailPixelSize(for: displaySize))
        let context: [SDWebImageContextOption: Any] =
            fullResolution
                ? [:] : [
                    .imageThumbnailPixelSize: pixelSize,
                    .imageDecodeOptions: [SDImageCoderOption.decodeScaleFactor: 1.0],

                    .storeCacheType: NSNumber(value: SDImageCacheType.memory.rawValue),
                    .originalStoreCacheType: NSNumber(value: SDImageCacheType.disk.rawValue),
                    .originalQueryCacheType: NSNumber(value: SDImageCacheType.disk.rawValue),
                ]
        ZStack {
            if !transparentBackground {
                MusicArtworkPlaceholder(cornerRadius: cornerRadius)
            }
            if let lowResURL, !fullLoaded {
                WebImage(
                    url: lowResURL,
                    options: [.retryFailed, .scaleDownLargeImages, .fromCacheOnly],
                    context: [.imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: 120, height: 120))]
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .clipped()
                        .blur(radius: 2)
                } placeholder: {
                    Color.clear
                }
            }
            if let url, !loadFailed {
                WebImage(
                    url: url,
                    options: ImageCacheConfig.defaultOptions,
                    context: context
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .clipped()
                        .onAppear {
                            markRendered(url)
                        }
                } placeholder: {
                    Color.clear
                }
                .onFailure { _ in
                    markFinishedAfterFailure(for: url)
                }
                .onSuccess { _, _, cacheType in
                    ArtworkLoadMetrics.shared.record(url: url, cacheType: cacheType)
                    markRendered(url)
                }
                .transition(.opacity.animation(AppMotion.spring(response: 0.15, dampingFraction: 0.9)))
            }
        }
    }

    private func markRendered(_ loadedURL: URL) {
        guard url == loadedURL, renderedFullURL != loadedURL || !fullLoaded || loadFailed else { return }
        Task { @MainActor in
            guard url == loadedURL, renderedFullURL != loadedURL || !fullLoaded || loadFailed else { return }
            withOptionalAnimation(AppMotion.spring(response: 0.12, dampingFraction: 0.9)) {
                renderedFullURL = loadedURL
                fullLoaded = true
                loadFailed = false
            }
        }
    }

    private func markFinishedAfterFailure(for failedURL: URL) {
        guard url == failedURL, !loadFailed else { return }
        evictFailedImageCache(for: failedURL)
        Task { @MainActor in
            guard url == failedURL, !loadFailed else { return }
            withOptionalAnimation(AppMotion.spring(response: 0.12, dampingFraction: 0.9)) {
                loadFailed = true
            }
        }
    }

    private func evictFailedImageCache(for failedURL: URL) {
        let cacheKey = failedURL.absoluteString
        SDImageCache.shared.removeImageFromMemory(forKey: cacheKey)
        SDImageCache.shared.removeImageFromDisk(forKey: cacheKey)
    }

    private func sanitizedDisplaySize(_ size: CGSize) -> CGSize {
        let width = size.width.isFinite ? max(size.width, 1) : 1
        let height = size.height.isFinite ? max(size.height, 1) : 1
        return CGSize(width: width, height: height)
    }

    private func thumbnailPixelSize(for displaySize: CGSize) -> CGSize {
        #if canImport(UIKit)
            let scale = UIScreen.main.scale
        #else
            let scale: CGFloat = 2
        #endif
        let w = max(displaySize.width, 1) * scale
        let h = max(displaySize.height, 1) * scale
        let cap = ImageCacheConfig.thumbnailPixelSize
        return CGSize(width: min(w, cap.width), height: min(h, cap.height))
    }
}

@MainActor
private final class ArtworkLoadMetrics {
    static let shared = ArtworkLoadMetrics()
    private var totalLoads = 0
    private var memoryHits = 0
    private var diskHits = 0
    private var networkLoads = 0
    private var lastReport = Date.distantPast

    func record(url _: URL, cacheType: SDImageCacheType) {
        totalLoads += 1
        switch cacheType {
        case .memory:
            memoryHits += 1
        case .disk:
            diskHits += 1
        case .none:
            networkLoads += 1
        default:
            break
        }

        let now = Date()
        guard totalLoads >= 20, now.timeIntervalSince(lastReport) > 20 else { return }
        lastReport = now
        DebugLogger.log(
            "Artwork loads: total=\(totalLoads), memory=\(memoryHits), disk=\(diskHits), network=\(networkLoads)",
            category: .cache
        )
    }
}

struct MusicArtworkPlaceholder: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            Color.appPlaceholderPrimary
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct CenteredLoadingView: View {
    var minHeight: CGFloat = 280
    var label: String = "Loading"

    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

struct MusicSkeletonShimmer: ViewModifier {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("nk.respectReducedMotion") private var respectReducedMotion: Bool = true
    @ObservedObject private var scrollState = ScrollPerformanceState.shared
    @State private var phase: CGFloat = -0.8

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    shimmer(width: proxy.size.width)
                        .opacity(effectiveActive ? 1 : 0)
                        .mask(content)
                }
                .clipShape(Rectangle())
                .allowsHitTesting(false)
            }
            .onAppear {
                restartIfNeeded(active: effectiveActive)
            }
            .onChange(of: effectiveActive) { _, effectiveActive in
                restartIfNeeded(active: effectiveActive)
            }
    }

    private var effectiveActive: Bool {
        isActive
            && !scrollState.isScrolling
            && !AppMotion.reduceMotion(
                systemReduceMotion: systemReduceMotion,
                respectPreference: respectReducedMotion
            )
    }

    private func restartIfNeeded(active: Bool) {
        if active {
            phase = -0.8
            withOptionalAnimation(AppMotion.spring(response: 1.65, dampingFraction: 0.9).repeatForever(autoreverses: false)) {
                phase = 1.8
            }
        } else {
            withOptionalAnimation(nil) {
                phase = -0.8
            }
        }
    }

    private func shimmer(width: CGFloat) -> some View {
        LinearGradient(
            colors: [
                .clear,
                .appPlaceholderSheen,
                .appPlaceholderSheenSoft,
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: max(width * 0.36, 56))
        .rotationEffect(.degrees(12))
        .offset(x: width * phase)
    }
}

extension View {
    func musicSkeletonShimmer(active: Bool) -> some View {
        modifier(MusicSkeletonShimmer(isActive: active))
    }
}

enum MusicSkeletonTone {
    case primary, secondary, tertiary, quaternary

    var color: Color {
        switch self {
        case .primary: .appPlaceholderPrimary
        case .secondary: .appPlaceholderSecondary
        case .tertiary: .appPlaceholderTertiary
        case .quaternary: .appPlaceholderQuaternary
        }
    }
}

struct MusicSkeletonBlock: View {
    var cornerRadius: CGFloat = 4
    var tone: MusicSkeletonTone = .primary
    var strokeOpacity: Double = 0.035

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tone.color)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 0.6)
            }
    }
}

struct MusicSkeletonLine: View {
    var width: CGFloat?
    var height: CGFloat = 13
    var tone: MusicSkeletonTone = .secondary

    var body: some View {
        MusicSkeletonBlock(cornerRadius: min(height / 2, 4), tone: tone, strokeOpacity: 0)
            .frame(width: width, height: height)
    }
}

struct MusicEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 15) {
            MusicEmptyStateMark()

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}

struct MusicEmptyActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.bold())
                .foregroundStyle(.primary)
                .padding(.horizontal, AM.Spacing.xl)
                .padding(.vertical, 11)
                .background(Color.appSecondaryBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.appDivider, lineWidth: 0.7)
                }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.94, dim: 0.78, haptic: .selection))
    }
}

struct MusicEmptyStateMark: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.appPlaceholderSecondary)
                .frame(width: 116, height: 82)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appDivider, lineWidth: 0.7)
                }

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appPlaceholderPrimary)
                .frame(width: 56, height: 56)
                .offset(x: 10, y: -13)

            VStack(alignment: .leading, spacing: 6) {
                MusicSkeletonLine(width: 38, height: 7, tone: .tertiary)
                MusicSkeletonLine(width: 28, height: 6, tone: .primary)
            }
            .offset(x: 75, y: -27)
        }
        .frame(width: 132, height: 96)
        .accessibilityHidden(true)
    }
}

struct MusicCircularPlaceholder: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(Color.appPlaceholderSecondary)
                Circle()
                    .fill(Color.appPlaceholderPrimary)
                    .frame(width: side * 0.48, height: side * 0.48)
                    .offset(x: -side * 0.08, y: -side * 0.08)
                MusicSkeletonLine(width: side * 0.30, height: max(side * 0.08, 4), tone: .tertiary)
                    .offset(x: side * 0.18, y: side * 0.20)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}
