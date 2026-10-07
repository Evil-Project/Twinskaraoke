import Foundation

nonisolated enum SplashFontFamily: String, Codable, CaseIterable {
    case system, rounded, serif, monospaced
}
nonisolated enum SplashFontWeight: String, Codable, CaseIterable {
    case regular, medium, semibold, bold
}
nonisolated enum SplashVerticalAlignment: String, Codable, CaseIterable {
    case top, center, bottom
}
nonisolated struct SplashTextStyle: Codable, Hashable {
    var size = 20.0
    var family: SplashFontFamily = .system
    var weight: SplashFontWeight = .regular
    /// Rejects unsupported or out-of-range content before it can be presented or exported.
    func validate(prefix: String) throws {
        guard size.isFinite, (12...72).contains(size) else {
            throw SplashError(message: prefix + "text size must be between 12 and 72.")
        }
    }
}

/// Coordinates and width are fractions of the available slide, never screen pixels.
nonisolated struct SplashPlacement: Codable, Hashable {
    var x = 0.5
    var y = 0.5
    var width = 0.85
    var height: Double?
    static let gridStep = 0.05
    /// Rounds normalized placement coordinates to the five-percent canvas grid.
    mutating func snapToGrid() {
        x = min(0.95, max(0.05, (x / Self.gridStep).rounded() * Self.gridStep))
        y = min(0.95, max(0.05, (y / Self.gridStep).rounded() * Self.gridStep))
        width = min(1, max(0.2, (width / Self.gridStep).rounded() * Self.gridStep))
        if let height { self.height = min(1.5, max(0.05, (height / Self.gridStep).rounded() * Self.gridStep)) }
    }
    /// Applies a normalized size delta while keeping the box within supported bounds.
    mutating func resize(dx: Double, dy: Double, measuredHeight: Double) {
        guard dx.isFinite, dy.isFinite, measuredHeight.isFinite else { return }
        width = min(1, max(0.2, width + dx))
        height = min(1.5, max(0.05, (height ?? measuredHeight) + dy))
    }
    /// Converts a finite positive scale factor into a bounded box resize.
    mutating func scale(by factor: Double, measuredHeight: Double) {
        guard factor.isFinite, factor > 0 else { return }
        resize(dx: width * (factor - 1), dy: (height ?? measuredHeight) * (factor - 1), measuredHeight: measuredHeight)
    }
    /// Applies a normalized movement delta while keeping the box on the canvas.
    mutating func move(dx: Double, dy: Double) {
        x = min(0.95, max(0.05, x + dx))
        y = min(0.95, max(0.05, y + dy))
    }
    /// Rejects unsupported or out-of-range content before it can be presented or exported.
    func validate(prefix: String) throws {
        guard x.isFinite, y.isFinite, width.isFinite,
              (0.05...0.95).contains(x), (0.05...0.95).contains(y),
              (0.2...1).contains(width),
              height == nil || (height!.isFinite && (0.05...1.5).contains(height!)) else {
            throw SplashError(message: prefix + "positions must be 5–95%, width 20–100%, and optional height 5–150%.")
        }
    }
}
nonisolated struct SplashSlideDesign: Codable, Hashable {
    var title = SplashTextStyle(size: 34, weight: .bold)
    var body = SplashTextStyle()
    var verticalAlignment: SplashVerticalAlignment = .top
    var imageCornerRadius = 0.0
    var imageWidth = 0.85
    var freeform = false
    var gridSnapping: Bool?
    var titlePlacement = SplashPlacement(y: 0.48)
    var bodyPlacement = SplashPlacement(y: 0.64)
    var imagePlacement = SplashPlacement(y: 0.22, width: 0.7)
    var demoPlacement = SplashPlacement(y: 0.78, width: 0.9)

    /// Initializes editable styles or mock controls with the chosen preset’s defaults.
    init(typography: SplashTypography = .standard) {
        if typography == .compact { title.size = 22; body.size = 17 }
        if typography == .large { title.family = .rounded }
    }
    /// Rejects unsupported or out-of-range content before it can be presented or exported.
    func validate(prefix: String) throws {
        try title.validate(prefix: prefix); try body.validate(prefix: prefix)
        for placement in [titlePlacement, bodyPlacement, imagePlacement, demoPlacement] {
            try placement.validate(prefix: prefix)
        }
        guard imageCornerRadius.isFinite, (0...80).contains(imageCornerRadius),
              imageWidth.isFinite, (0.2...1).contains(imageWidth) else {
            throw SplashError(message: prefix + "image corners must be 0–80 and image width 20–100%.")
        }
    }
}

nonisolated enum SplashDemoKind: String, Codable, CaseIterable, Identifiable {
    case songRow, miniPlayer, albumCard, playPause, favorite, search, tabs, settingsToggle, volume, lyrics
    var id: String { rawValue }
    var label: String {
        switch self {
        case .songRow: "Song Row"
        case .miniPlayer: "Mini Player"
        case .albumCard: "Album Card"
        case .playPause: "Play / Pause"
        case .favorite: "Favorite Button"
        case .search: "Search Field"
        case .tabs: "App Tabs"
        case .settingsToggle: "Settings Toggle"
        case .volume: "Volume Slider"
        case .lyrics: "Lyrics"
        }
    }
}
nonisolated enum SplashDemoTab: String, Codable, CaseIterable {
    case home, new, radio, library, search
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: "house"; case .new: "square.grid.2x2"; case .radio: "dot.radiowaves.left.and.right"
        case .library: "music.note.list"; case .search: "magnifyingglass"
        }
    }
}
nonisolated struct SplashDemoFeature: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var kind: SplashDemoKind
    var title = "Song title"
    var subtitle = "Artist placeholder"
    var initialValue = false
    var initialProgress = 0.5
    var accentColor = "#FA3155"
    var backgroundColor = "#1C2639"
    var textColor = "#FFFFFF"
    var cornerRadius = 16.0
    var textStyle = SplashTextStyle(size: 17)
    var placement = SplashPlacement(y: 0.75)
    var highlighted = false
    var imageData: Data?
    var imageDescription = "Artwork placeholder"
    var initialTab: SplashDemoTab?
    var initialText: String?
    /// Initializes editable styles or mock controls with the chosen preset’s defaults.
    init(kind: SplashDemoKind) {
        self.kind = kind
        switch kind {
        case .settingsToggle: title = "Setting label"; subtitle = "Description placeholder"
        case .search: title = "Search songs"; subtitle = ""
        case .lyrics: title = "Lyrics placeholder"; subtitle = "Next line placeholder"
        case .volume: title = "Volume"; subtitle = ""
        case .favorite: title = "Favorite"; subtitle = ""
        case .playPause: title = "Play / Pause"; subtitle = ""
        default: break
        }
    }
    /// Rejects unsupported or out-of-range content before it can be presented or exported.
    static func validate(_ features: [Self], prefix: String) throws {
        guard features.count <= 12, Set(features.map(\.id)).count == features.count else {
            throw SplashError(message: prefix + "use up to 12 app features with unique IDs.")
        }
        for feature in features {
            guard SplashContent.validID(feature.id), feature.title.count <= 300, feature.subtitle.count <= 2000, (feature.initialText?.count ?? 0) <= 300,
                  [feature.accentColor, feature.backgroundColor, feature.textColor].allSatisfy(SplashContent.validColor),
                  feature.initialProgress.isFinite, (0...1).contains(feature.initialProgress),
                  feature.cornerRadius.isFinite, (0...80).contains(feature.cornerRadius) else {
                throw SplashError(message: prefix + "invalid app feature text, color, value or corner size.")
            }
            try feature.textStyle.validate(prefix: prefix)
            try feature.placement.validate(prefix: prefix)
            if let data = feature.imageData {
                try SplashContent.validateImage(data, description: feature.imageDescription, prefix: prefix)
            }
        }
    }
}
nonisolated struct SplashDemoStep: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var title = "Demo step"
    var caption = "Instruction placeholder"
    var advanceOnInteraction = false
    var features = [SplashDemoFeature(kind: .miniPlayer)]
}
nonisolated struct SplashDemonstration: Codable, Hashable {
    var steps = [SplashDemoStep()]
    /// Rejects unsupported or out-of-range content before it can be presented or exported.
    func validate(prefix: String) throws {
        guard (1...12).contains(steps.count), Set(steps.map(\.id)).count == steps.count else {
            throw SplashError(message: prefix + "a demonstration needs 1–12 steps with unique IDs.")
        }
        for step in steps {
            guard SplashContent.validID(step.id), step.title.count <= 300, step.caption.count <= 2000,
                  !step.features.isEmpty else {
                throw SplashError(message: prefix + "each demo step needs an app feature and bounded text.")
            }
            try SplashDemoFeature.validate(step.features, prefix: prefix)
        }
    }
}

extension SplashSlide {
    var resolvedDesign: SplashSlideDesign { design ?? SplashSlideDesign(typography: typography) }
}
