import SDWebImageSwiftUI
import SwiftUI
import Observation

struct RemoteArtworkImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var contentMode: ContentMode = .fill
    var lowResURL: URL?
    var transparentBackground: Bool = false
    var fullResolution: Bool = false

    var fixedDisplaySize: CGSize?
    private let scrollState = ScrollPerformanceState.shared
    // Observed so a view composed during a failure-backoff window re-evaluates
    // isBlocked when the window ends instead of showing the placeholder forever.
    private let failureBackoff = ArtworkFailureBackoff.shared
    @State private var fullLoaded: Bool = false
    @State private var renderedFullURL: URL?
    var body: some View {
        // Load-bearing read: `isBlocked(url)` below is a method call over
        // NSLock-guarded storage and registers nothing with observation.
        // `generation` is the publish signal, so reading it here is what
        // recomposes this view when a backoff window ends. Under
        // @ObservedObject merely holding `failureBackoff` was enough.
        let _ = failureBackoff.generation
        return Group {
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
            renderedFullURL = nil
        }
    }

    @ViewBuilder
    private func imageContent(size: CGSize) -> some View {
        let displaySize = sanitizedDisplaySize(size)
        let context = fullResolution ? ImageCacheConfig.memoryAndDiskCacheContext : ImageCacheConfig.visibleImageContext
        // Fast path: the bitmap is already in the memory cache, so paint it in
        // this very body pass. `WebImage` cannot do this — it decides to show
        // the placeholder before it starts the load — which costs one grey
        // frame per row even on a hit. See `ArtworkMemoryCache`.
        if let cached = ArtworkMemoryCache.image(for: url) {
            cached
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: displaySize.width, height: displaySize.height)
                .clipped()
        } else {
            asyncImageContent(displaySize: displaySize, context: context)
        }
    }

    @ViewBuilder
    private func asyncImageContent(
        displaySize: CGSize,
        context: [SDWebImageContextOption: Any]
    ) -> some View {
        ZStack {
            if !transparentBackground {
                MusicArtworkPlaceholder(cornerRadius: cornerRadius)
            }
            if let lowResURL, !fullLoaded, shouldPreferProgressiveArtwork {
                // The blur variant is a ~1 KB WebP; loading it (not just from
                // cache) gives every image a progressive preview, even when the
                // prefetcher hasn't warmed this URL yet.
                WebImage(
                    url: lowResURL,
                    options: ImageCacheConfig.defaultOptions,
                    context: context
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .clipped()
                        .blur(radius: scrollState.isScrolling ? 0 : 2)
                } placeholder: {
                    Color.clear
                }
            }
            if let url, !ArtworkFailureBackoff.shared.isBlocked(url) {
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
                            deferMarkRendered(url)
                        }
                } placeholder: {
                    Color.clear
                }
                .onFailure { error in
                    markFinishedAfterFailure(for: url, error: error)
                }
                .onSuccess { _, _, cacheType in
                    // Memory-cache hits complete synchronously while SwiftUI is still
                    // evaluating this view; writing @State here trips "Modifying state
                    // during view update". Defer the write to the next runloop turn.
                    deferMarkRendered(url, cacheType: cacheType)
                }
                .transition(
                    shouldAnimateLoad
                        ? .opacity.animation(AppMotion.spring(response: 0.15, dampingFraction: 0.9))
                        : .identity
                )
            }
        }
    }

    private func deferMarkRendered(_ loadedURL: URL, cacheType: SDImageCacheType? = nil) {
        DispatchQueue.main.async {
            if let cacheType {
                ArtworkLoadMetrics.shared.record(cacheType: cacheType)
            }
            markRendered(loadedURL)
        }
    }

    @MainActor
    private func markRendered(_ loadedURL: URL) {
        guard url == loadedURL, renderedFullURL != loadedURL || !fullLoaded else { return }
        withOptionalAnimation(loadAnimation) {
            renderedFullURL = loadedURL
            fullLoaded = true
        }
        ArtworkFailureBackoff.shared.clear(loadedURL)
    }

    private func markFinishedAfterFailure(for failedURL: URL, error: Error) {
        guard url == failedURL else { return }

        let safeURL = Self.redactedURLString(failedURL)
        DebugLogger.log(
            "Artwork load failed for \(safeURL): \(error.localizedDescription)",
            category: .cache
        )
        // The shared backoff is the single retry owner. Its generation update
        // removes this WebImage immediately, and its scheduled expiry
        // recomposes every view for the URL after the cooldown. A per-view
        // five-minute Task here duplicated that timer and retained off-screen
        // view state throughout CDN outages.
        ArtworkFailureBackoff.shared.recordFailure(failedURL)
        evictFailedImageCache(for: failedURL)
    }

    private var shouldAnimateLoad: Bool {
        !scrollState.isScrolling && shouldPreferProgressiveArtwork
    }

    /// Whether to show the ~1 KB blurred preview while the real image loads.
    ///
    /// This used to require a display size over 96pt, which excluded song rows
    /// (44–48pt) — precisely where fast scrolling leaves a flat grey
    /// placeholder on screen the longest. A blurred preview is a far better
    /// stand-in than grey, and at a few hundred bytes it arrives about as fast
    /// as the network can answer at all.
    ///
    /// The floor stays low rather than disappearing: below ~24pt the preview is
    /// too small to read as anything, so the extra image layer per row buys
    /// nothing.
    private var shouldPreferProgressiveArtwork: Bool {
        guard let fixedDisplaySize else { return true }
        return max(fixedDisplaySize.width, fixedDisplaySize.height) >= 24
    }

    private var loadAnimation: Animation? {
        shouldAnimateLoad ? AppMotion.spring(response: 0.12, dampingFraction: 0.9) : nil
    }

    private static func redactedURLString(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? url.lastPathComponent
    }

    private func evictFailedImageCache(for failedURL: URL) {
        let cacheKey = failedURL.absoluteString
        // Async variant: removes from memory immediately and evicts the disk
        // entry off the calling (main) queue.
        SDImageCache.shared.removeImage(forKey: cacheKey, fromDisk: true, withCompletion: nil)
    }

    private func sanitizedDisplaySize(_ size: CGSize) -> CGSize {
        let width = size.width.isFinite ? max(size.width, 1) : 1
        let height = size.height.isFinite ? max(size.height, 1) : 1
        return CGSize(width: width, height: height)
    }

}

@Observable
final class ArtworkFailureBackoff {
    static let shared = ArtworkFailureBackoff()

    private let cooldown: TimeInterval = 300
    private let lock = NSLock()
    // MUST stay out of the observation graph. It is NSLock-guarded, written off
    // the main actor, and mutated from `clear(_:)` on the render path. Observing
    // it publishes on every `removeValue` — even one that removes nothing —
    // which re-enters the SwiftUI graph synchronously and recurses forever
    // (markRendered -> clear -> willSet -> flushTransactions -> body -> ...).
    // `generation` below is the intended publish signal precisely because its
    // bump is guarded by "did anything actually change".
    @ObservationIgnored private var blockedUntil: [URL: Date] = [:]

    // Bumped whenever the blocked set changes so observing views re-evaluate
    // isBlocked. Never written from isBlocked itself — that runs during view
    // body evaluation, where publishing a change is illegal.
    private(set) var generation = 0

    var cooldownDuration: Duration {
        .seconds(cooldown)
    }

    func isBlocked(_ url: URL) -> Bool {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        guard let until = blockedUntil[url] else { return false }
        // Don't remove elapsed entries here: expire(_:) removes them and
        // bumps generation, which is what recomposes blocked views. Removing
        // here would skip that publish and leave those views on the
        // placeholder until they are recreated.
        return until > now
    }

    func recordFailure(_ url: URL) {
        lock.lock()
        if blockedUntil.count > 256 {
            let now = Date()
            blockedUntil = blockedUntil.filter { $0.value > now }
        }
        blockedUntil[url] = Date().addingTimeInterval(cooldown)
        lock.unlock()
        bumpGeneration()
        // Views composed while this URL is blocked render no WebImage and
        // schedule no retry of their own; unblock proactively so they
        // recompose when the cooldown ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldown) { [weak self] in
            self?.expire(url)
        }
    }

    func clear(_ url: URL) {
        lock.lock()
        let removed = blockedUntil.removeValue(forKey: url) != nil
        lock.unlock()
        if removed { bumpGeneration() }
    }

    private func expire(_ url: URL) {
        lock.lock()
        // A failure re-recorded after this expiry was scheduled extends the
        // deadline; only remove entries whose window actually ended.
        let expired = blockedUntil[url].map { $0 <= Date() } ?? false
        if expired {
            blockedUntil.removeValue(forKey: url)
        }
        lock.unlock()
        if expired { bumpGeneration() }
    }

    private func bumpGeneration() {
        if Thread.isMainThread {
            generation += 1
        } else {
            DispatchQueue.main.async { self.generation += 1 }
        }
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

    func record(cacheType: SDImageCacheType) {
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
        let reportedTotal = totalLoads
        let reportedMemory = memoryHits
        let reportedDisk = diskHits
        let reportedNetwork = networkLoads
        totalLoads = 0
        memoryHits = 0
        diskHits = 0
        networkLoads = 0
        DebugLogger.log(
            "Artwork loads: total=\(reportedTotal), memory=\(reportedMemory), disk=\(reportedDisk), network=\(reportedNetwork)",
            category: .cache
        )
    }
}

struct MusicArtworkPlaceholder: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.appPlaceholderPrimary
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
    @Environment(\.appReduceMotion) private var reduceMotion
    private let scrollState = ScrollPerformanceState.shared
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
            && !reduceMotion
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
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var appeared = false

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
        .opacity(appeared || reduceMotion ? 1 : 0)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.97)
        .onAppear {
            guard !appeared else { return }
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(AppMotion.standard) {
                appeared = true
            }
        }
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
