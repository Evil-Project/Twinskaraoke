import CoreGraphics
import Foundation
import QuartzCore
import Observation

#if canImport(UIKit)
    import UIKit
#endif

/// One on-screen creature. Position/animation state live here; the engine
/// owns the shared physics tick, `ShimejiSpriteView` just renders whatever
/// this currently says.
@Observable
final class ShimejiInstance: Identifiable {
    enum Motion {
        case falling
        case idle
        case walking
        case climbing
        case dragged
        case sitting
    }

    let id = UUID()
    let character: ShimejiCharacterDefinition

    var position: CGPoint
    var action: ShimejiActionKind = .fall
    var frameIndex: Int = 0
    var facingRight: Bool = true

    var motion: Motion = .falling
    var velocityX: CGFloat = 0
    var velocityY: CGFloat = 0
    var walkDirection: CGFloat = Bool.random() ? 1 : -1
    var stateTimer: Double = 0
    var frameTimer: Double = 0
    var climbingOnLeftEdge = false

    /// Set true while a drag gesture owns this instance's position; the
    /// physics tick skips motion updates (but keeps animating) until released.
    var isDragHeld = false

    /// Tracks recent drag motion so a release can carry it forward as real
    /// throw momentum instead of just dropping straight down.
    var lastDragSample: (point: CGPoint, time: CFTimeInterval)?
    var dragVelocity: CGPoint = .zero

    init(character: ShimejiCharacterDefinition, position: CGPoint) {
        self.character = character
        self.position = position
    }

    /// Frames for the current action, falling back to "stand" if this
    /// character's pack doesn't define a pose for it (e.g. no "sit").
    var currentFrames: [String] {
        (character.action(action) ?? character.action(.stand))?.frames ?? []
    }

    var currentFrameDuration: Double {
        (character.action(action) ?? character.action(.stand))?.frameDuration ?? 0.2
    }
}

/// Drives every on-screen Shimeji: spawn/despawn, the shared physics/AI tick,
/// and drag interaction. One instance lives for the app's lifetime.
/// Drives every on-screen Shimeji: spawn/despawn, the shared physics/AI tick,
/// and drag interaction. One instance lives for the app's lifetime.
@MainActor
@Observable
final class ShimejiEngine: NSObject {
    static let shared = ShimejiEngine()
    /// Rendered sprite size in points; shared with ShimejiSpriteView (visual
    /// size) and the overlay window's hitTest (touch target) so both agree
    /// on where a sprite actually is on screen.
    static let displaySize: CGFloat = 84

    private(set) var instances: [ShimejiInstance] = []
    var bounds: CGRect = .zero

    /// The app's actual tab bar top edge, in the same coordinate space as
    /// `bounds`, kept fresh by `ShimejiOverlayController`'s periodic poll of
    /// the live `UITabBar`. Nil when there's no tab bar to find.
    var navBarY: CGFloat?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    private let gravity: CGFloat = 850
    private let walkSpeed: CGFloat = 42
    private let climbSpeed: CGFloat = 50
    private let spriteHalfWidth: CGFloat = 42

    private var climbEdgeInset: CGFloat {
        spriteHalfWidth - 40
    }

    private var allowClimbing: Bool {
        (UserDefaults.standard.object(forKey: "nk.shimeji.canClimb") as? Bool) ?? true
    }

    // MARK: - Mini player floor

    private(set) var hasMiniPlayer: Bool = false {
        didSet {
            guard hasMiniPlayer != oldValue else { return }
            handleFloorTargetChange()
        }
    }

    var isNowPlayingOpen: Bool = false {
        didSet {
            guard isNowPlayingOpen != oldValue else { return }
            handleFloorTargetChange()
        }
    }

    var miniPlayerY: CGFloat? {
        didSet {
            guard miniPlayerY != oldValue, hasMiniPlayer, !isNowPlayingOpen else { return }
            handleFloorTargetChange()
        }
    }

    private var playbackObservation: ObservationToken?

    override private init() {
        super.init()
        observePlaybackState()
    }

    private func observePlaybackState() {
        // The guarded assignments below replace `removeDuplicates`: only the
        // presence of a song matters here, so most `currentSong` changes are
        // no-ops for the overlay and must not restart its animation.
        playbackObservation = observeContinuously({
            _ = AudioPlayerManager.shared.currentSong
            _ = NowPlayingPresentation.shared.isExpanded
        }, onChange: { [weak self] in
            self?.syncPlaybackState()
        })
        syncPlaybackState()
    }

    private func syncPlaybackState() {
        let hasSong = AudioPlayerManager.shared.currentSong != nil
        if hasMiniPlayer != hasSong { hasMiniPlayer = hasSong }
        let isExpanded = NowPlayingPresentation.shared.isExpanded
        if isNowPlayingOpen != isExpanded { isNowPlayingOpen = isExpanded }
    }

    // MARK: - Lifecycle

    func start(manifest: ShimejiManifest) {
        guard displayLink == nil else { return }
        respawn(manifest: manifest)
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        instances.removeAll()
    }

    func respawn(manifest: ShimejiManifest) {
        let settings = ShimejiSpawnSettings.load()
        let enabledIDs = settings.enabledIDs(for: manifest)
        let pool = manifest.characters.filter { enabledIDs.contains($0.id) }
        guard !pool.isEmpty, bounds.width > 0 else {
            instances = []
            return
        }
        let count = min(settings.maxCount, 12)
        instances = (0 ..< count).map { _ in
            let character = pool.randomElement()!
            let x = CGFloat.random(in: bounds.minX + spriteHalfWidth ... max(bounds.minX + spriteHalfWidth, bounds.maxX - spriteHalfWidth))
            return ShimejiInstance(character: character, position: CGPoint(x: x, y: bounds.minY))
        }
    }

    // MARK: - Drag interaction

    func beginDrag(_ instance: ShimejiInstance) {
        instance.isDragHeld = true
        instance.motion = .dragged
        instance.action = .dragged
    }

    func updateDrag(_ instance: ShimejiInstance, to point: CGPoint) {
        let now = CACurrentMediaTime()
        if let last = instance.lastDragSample {
            let dt = now - last.time
            if dt > 0.008 {
                let vx = (point.x - last.point.x) / CGFloat(dt)
                let vy = (point.y - last.point.y) / CGFloat(dt)
                instance.dragVelocity = CGPoint(
                    x: instance.dragVelocity.x * 0.75 + vx * 0.25,
                    y: instance.dragVelocity.y * 0.75 + vy * 0.25
                )
            }
        }
        instance.lastDragSample = (point, now)
        instance.position = point
    }

    func endDrag(_ instance: ShimejiInstance) {
        instance.isDragHeld = false
        instance.motion = .falling
        let throwSensitivity: CGFloat = 0.35
        let maxThrowSpeed: CGFloat = 900
        instance.velocityX = min(maxThrowSpeed, max(-maxThrowSpeed, instance.dragVelocity.x * throwSensitivity))
        instance.velocityY = min(maxThrowSpeed, max(-maxThrowSpeed, instance.dragVelocity.y * throwSensitivity))
        instance.dragVelocity = .zero
        instance.lastDragSample = nil
        instance.action = .fall
    }

    // MARK: - Physics tick

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(1.0 / 30.0, link.timestamp - (lastTimestamp ?? link.timestamp))
        lastTimestamp = link.timestamp
        guard dt > 0, bounds.width > 0 else { return }

        for instance in instances {
            advance(instance, dt: dt)
            advanceFrame(instance, dt: dt)
        }
    }

    private func advanceFrame(_ instance: ShimejiInstance, dt: Double) {
        let frames = instance.currentFrames
        guard frames.count > 1 else {
            if instance.frameIndex != 0 { instance.frameIndex = 0 }
            return
        }
        instance.frameTimer += dt
        if instance.frameTimer >= instance.currentFrameDuration {
            instance.frameTimer = 0
            instance.frameIndex = (instance.frameIndex + 1) % frames.count
        }
    }

    private func advance(_ instance: ShimejiInstance, dt: Double) {
        guard !instance.isDragHeld else { return }

        if instance.motion == .idle || instance.motion == .sitting {
            if !isStillSupported(instance) {
                instance.motion = .falling
            }
        }

        switch instance.motion {
        case .dragged:
            break

        case .falling:
            instance.velocityY += gravity * CGFloat(dt)
            instance.position.y += instance.velocityY * CGFloat(dt)
            instance.position.x += instance.velocityX * CGFloat(dt)
            if instance.velocityX > 4 { instance.facingRight = true }
            else if instance.velocityX < -4 { instance.facingRight = false }

            let drag = pow(0.02, CGFloat(dt))
            instance.velocityX *= drag
            instance.action = .fall

            if instance.position.x < bounds.minX + spriteHalfWidth {
                if !grabWallIfPossible(instance, onLeftEdge: true) {
                    instance.position.x = bounds.minX + spriteHalfWidth
                }
            } else if instance.position.x > bounds.maxX - spriteHalfWidth {
                if !grabWallIfPossible(instance, onLeftEdge: false) {
                    instance.position.x = bounds.maxX - spriteHalfWidth
                }
            }

            guard instance.motion == .falling else { return }

            if instance.velocityY >= 0, instance.position.y >= currentFloorY {
                instance.position.y = currentFloorY
                instance.velocityY = 0
                instance.velocityX = 0
                instance.motion = .idle
                instance.stateTimer = Double.random(in: 0.6 ... 2.2)
                instance.action = .stand
            } else if instance.position.y > bounds.maxY + 200 {
                instance.position.y = bounds.minY
                instance.position.x = CGFloat.random(in: bounds.minX ... bounds.maxX)
                instance.velocityX = 0
            }

        case .idle:
            instance.action = .stand
            instance.stateTimer -= dt
            if instance.stateTimer <= 0 {
                if Bool.random() {
                    instance.motion = .walking
                    instance.walkDirection = Bool.random() ? 1 : -1
                    instance.stateTimer = Double.random(in: 1.2 ... 4.0)
                } else if character(instance).action(.sit) != nil, Bool.random() {
                    instance.motion = .sitting
                    instance.stateTimer = Double.random(in: 2 ... 5)
                } else {
                    instance.stateTimer = Double.random(in: 0.6 ... 2.0)
                }
            }

        case .sitting:
            instance.action = .sit
            instance.stateTimer -= dt
            if instance.stateTimer <= 0 {
                instance.motion = .idle
                instance.stateTimer = Double.random(in: 0.4 ... 1.4)
            }

        case .walking:
            instance.action = .walk
            instance.facingRight = instance.walkDirection > 0
            instance.position.x += instance.walkDirection * walkSpeed * CGFloat(dt)
            instance.stateTimer -= dt

            let atRightEdge = instance.position.x >= bounds.maxX - spriteHalfWidth
            let atLeftEdge = instance.position.x <= bounds.minX + spriteHalfWidth
            if atRightEdge || atLeftEdge {
                instance.position.x = atRightEdge ? bounds.maxX - spriteHalfWidth : bounds.minX + spriteHalfWidth
                if allowClimbing, character(instance).action(.climb) != nil, Bool.random() {
                    instance.motion = .climbing
                    instance.climbingOnLeftEdge = atLeftEdge
                    instance.facingRight = atRightEdge
                    instance.position.x = atLeftEdge ? bounds.minX + climbEdgeInset : bounds.maxX - climbEdgeInset
                    instance.stateTimer = Double.random(in: 1.0 ... 3.0)
                } else {
                    instance.walkDirection *= -1
                    instance.stateTimer = Double.random(in: 1.0 ... 3.0)
                }
            } else if instance.stateTimer <= 0 {
                if Bool.random() {
                    instance.motion = .falling
                } else {
                    instance.motion = .idle
                    instance.stateTimer = Double.random(in: 0.5 ... 2.0)
                }
            } else if instance.position.y < currentFloorY - 1 {
                instance.motion = .falling
            }

        case .climbing:
            guard allowClimbing else {
                instance.motion = .falling
                break
            }
            instance.action = .climb
            instance.position.y -= climbSpeed * CGFloat(dt)
            instance.stateTimer -= dt

            let climbTopLimit = bounds.minY + Self.displaySize
            if instance.position.y < climbTopLimit {
                instance.position.y = climbTopLimit
            }

            if instance.stateTimer <= 0 || instance.position.y <= climbTopLimit {
                instance.motion = .falling
                instance.velocityY = 0
                instance.position.x = instance.climbingOnLeftEdge
                    ? bounds.minX + spriteHalfWidth + 8
                    : bounds.maxX - spriteHalfWidth - 8
                instance.velocityX = instance.climbingOnLeftEdge ? 70 : -70
            }
        }
    }

    /// The screen bottom — when Now Playing is expanded, bypass navBarY so
    /// Shimejis fall past the nav bar all the way to bounds.maxY.
    private var groundY: CGFloat {
        if isNowPlayingOpen {
            return bounds.maxY
        }
        return navBarY ?? bounds.maxY
    }

    private var currentFloorY: CGFloat {
        if hasMiniPlayer, !isNowPlayingOpen, let y = miniPlayerY {
            return y
        }
        return groundY
    }

    private func isStillSupported(_ instance: ShimejiInstance) -> Bool {
        abs(currentFloorY - instance.position.y) < 2
    }

    /// Triggers when the active floor changes position (opening/closing Now Playing or starting/ending a song).
    private func handleFloorTargetChange() {
        let target = currentFloorY

        for instance in instances where !instance.isDragHeld {
            let gap = instance.position.y - target

            // If target moved DOWN (e.g. Now Playing opened), force them to fall
            if gap < -2 {
                if instance.motion != .falling && instance.motion != .climbing {
                    instance.motion = .falling
                    instance.action = .fall
                }
            }
            // If target moved UP (e.g. Now Playing closed), hop up to reach it
            else if gap > 2 {
                let impulse = sqrt(2 * gravity * gap) * 1.15 + 60
                instance.motion = .falling
                instance.velocityY = -impulse
                instance.velocityX = CGFloat.random(in: -30 ... 30)
                instance.stateTimer = 0
                instance.action = .fall
            }
        }
    }

    private func character(_ instance: ShimejiInstance) -> ShimejiCharacterDefinition {
        instance.character
    }

    @discardableResult
    private func grabWallIfPossible(_ instance: ShimejiInstance, onLeftEdge: Bool) -> Bool {
        guard allowClimbing, character(instance).action(.climb) != nil else {
            instance.velocityX = 0
            return false
        }
        instance.motion = .climbing
        instance.climbingOnLeftEdge = onLeftEdge
        instance.facingRight = !onLeftEdge
        instance.position.x = onLeftEdge ? bounds.minX + climbEdgeInset : bounds.maxX - climbEdgeInset
        instance.velocityX = 0
        instance.velocityY = 0
        instance.stateTimer = Double.random(in: 1.0 ... 3.0)
        return true
    }
}

/// Which characters spawn and how many at once — user-editable in
/// ShimejiSettingsView, persisted to UserDefaults directly (rather than
/// @AppStorage) since it's an array/struct, not a primitive.
struct ShimejiSpawnSettings: Codable {
    var enabledCharacterIDs: Set<String>
    var maxCount: Int
    /// nil means "never touched the character list" (old data, or first
    /// run) — falls back to every character. Once set, the person's exact
    /// choice is honored, including choosing zero characters via "Use None".
    var hasCustomizedCharacters: Bool?

    private static let key = "nk.shimeji.spawnSettings"

    static func load() -> ShimejiSpawnSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(ShimejiSpawnSettings.self, from: data)
        else {
            return ShimejiSpawnSettings(enabledCharacterIDs: [], maxCount: 3, hasCustomizedCharacters: nil)
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: ShimejiSpawnSettings.key)
    }

    /// Which characters should actually spawn for a given manifest.
    func enabledIDs(for manifest: ShimejiManifest) -> Set<String> {
        if hasCustomizedCharacters == true {
            return enabledCharacterIDs
        }
        if hasCustomizedCharacters == nil, !enabledCharacterIDs.isEmpty {
            return enabledCharacterIDs
        }
        return Set(manifest.characters.map(\.id))
    }
}
