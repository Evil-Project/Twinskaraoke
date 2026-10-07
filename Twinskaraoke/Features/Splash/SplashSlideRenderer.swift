import SwiftUI
import UIKit

struct SplashStyledText: View {
    let text: String
    let style: SplashTextStyle
    var header = false
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    init(text: String, style: SplashTextStyle, header: Bool = false) {
        self.text = text; self.style = style; self.header = header
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: header ? .largeTitle : .body)
    }
    var body: some View {
        Text(text).font(.system(size: style.size * scale, weight: weight, design: design))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(header ? .isHeader : [])
    }
    private var weight: Font.Weight {
        switch style.weight { case .regular: .regular; case .medium: .medium; case .semibold: .semibold; case .bold: .bold }
    }
    private var design: Font.Design {
        switch style.family { case .system: .default; case .rounded: .rounded; case .serif: .serif; case .monospaced: .monospaced }
    }
}

enum SplashCanvasItem: Hashable, Identifiable {
    case title, body, image, demonstration, feature(String)
    var id: String {
        switch self {
        case .title: "title"; case .body: "body"; case .image: "image"; case .demonstration: "demonstration"
        case .feature(let id): "feature-\(id)"
        }
    }
    var label: String {
        switch self {
        case .title: "Title"; case .body: "Body"; case .image: "Image / Symbol"
        case .demonstration: "Interaction Slideshow"; case .feature: "App Feature"
        }
    }
}

extension SplashSlide {
    var canvasItems: [SplashCanvasItem] {
        var items: [SplashCanvasItem] = []
        if layout == .imageAbove && (imageData != nil || symbol != nil) { items.append(.image) }
        if !(title ?? "").isEmpty { items.append(.title) }
        if !(body ?? "").isEmpty { items.append(.body) }
        if layout == .textAbove && (imageData != nil || symbol != nil) { items.append(.image) }
        items += (features ?? []).map { .feature($0.id) }
        if demonstration != nil { items.append(.demonstration) }
        return items
    }
    func placement(for item: SplashCanvasItem) -> SplashPlacement {
        switch item {
        case .title: resolvedDesign.titlePlacement
        case .body: resolvedDesign.bodyPlacement
        case .image: resolvedDesign.imagePlacement
        case .demonstration: resolvedDesign.demoPlacement
        case .feature(let id): features?.first { $0.id == id }?.placement ?? SplashPlacement()
        }
    }
    mutating func setPlacement(_ placement: SplashPlacement, for item: SplashCanvasItem) {
        if design == nil { design = resolvedDesign }
        switch item {
        case .title: design?.titlePlacement = placement
        case .body: design?.bodyPlacement = placement
        case .image: design?.imagePlacement = placement
        case .demonstration: design?.demoPlacement = placement
        case .feature(let id):
            if let index = features?.firstIndex(where: { $0.id == id }) { features?[index].placement = placement }
        }
    }
}

private struct SplashMeasurements: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private struct SplashCanvasEditing: ViewModifier {
    let select: (() -> Void)?
    let move: ((Double, Double) -> Void)?
    let width: CGFloat
    let height: CGFloat
    let resize: ((Double, Double, Double) -> Void)?
    let selected: Bool
    let finish: (() -> Void)?
    let grid: Bool
    @Environment(\.layoutDirection) private var direction
    @ViewBuilder func body(content: Content) -> some View {
        if let select, let move {
            content.overlay {
                SplashCanvasTouchSurface(select: select, move: { dx, dy in
                    move((direction == .rightToLeft ? -dx : dx) / width, dy / height)
                }, resize: { dx, dy, measuredHeight in
                    resize?(dx / width, dy / height, measuredHeight / height)
                }, selected: selected, finish: { finish?() }).accessibilityHidden(true)
            }
            .accessibilityAction(named: "Expand box") { resize?(0.05, 0.05, 0.2); finish?() }
            .accessibilityAction(named: "Contract box") { resize?(-0.05, -0.05, 0.2); finish?() }
            .accessibilityAction(named: "Move up") { move(0, grid ? -0.05 : -0.025) }
            .accessibilityAction(named: "Move down") { move(0, grid ? 0.05 : 0.025) }
            .accessibilityAction(named: "Move left") { move((direction == .rightToLeft ? 1 : -1) * (grid ? 0.05 : 0.025), 0) }
            .accessibilityAction(named: "Move right") { move((direction == .rightToLeft ? -1 : 1) * (grid ? 0.05 : 0.025), 0) }
        } else { content }
    }
}

private struct SplashCanvasContainerAccessibility: ViewModifier {
    let editing: Bool
    let identifier: String
    @ViewBuilder func body(content: Content) -> some View {
        if editing { content.accessibilityElement(children: .contain).accessibilityIdentifier(identifier) }
        else { content.accessibilityIdentifier(identifier) }
    }
}

/// UIKit keeps editing touches inside the actual tile, independent of the scrolling inspector.
private struct SplashCanvasTouchSurface: UIViewRepresentable {
    let select: () -> Void
    let move: (Double, Double) -> Void
    let resize: (Double, Double, Double) -> Void
    let selected: Bool
    let finish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(select: select, move: move, resize: resize, selected: selected, finish: finish) }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.drag(_:)))
        pan.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pan); view.addGestureRecognizer(tap); view.addGestureRecognizer(pinch)
        view.pan = pan; view.pinch = pinch
        return view
    }
    func updateUIView(_ view: Surface, context: Context) {
        context.coordinator.select = select; context.coordinator.move = move
        context.coordinator.resize = resize; context.coordinator.selected = selected
        context.coordinator.finish = finish
        view.protectItemDrag()
    }
    final class Surface: UIView {
        var pan: UIPanGestureRecognizer?
        var pinch: UIPinchGestureRecognizer?
        private weak var protectedScroll: UIScrollView?
        override func didMoveToWindow() { super.didMoveToWindow(); protectItemDrag() }
        func protectItemDrag() {
            guard let pan else { return }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    guard protectedScroll !== scroll else { return }
                    protectedScroll = scroll
                    scroll.panGestureRecognizer.require(toFail: pan)
                    if let pinch { scroll.panGestureRecognizer.require(toFail: pinch) }
                    break
                }
                ancestor = view.superview
            }
        }
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.contains(point) }
    }
    final class Coordinator: NSObject {
        var select: () -> Void
        var move: (Double, Double) -> Void
        var resize: (Double, Double, Double) -> Void
        var selected: Bool
        var finish: () -> Void
        private var previous = CGPoint.zero
        private var previousScale: CGFloat = 1
        private var pulling = false
        init(select: @escaping () -> Void, move: @escaping (Double, Double) -> Void, resize: @escaping (Double, Double, Double) -> Void, selected: Bool, finish: @escaping () -> Void) {
            self.select = select; self.move = move; self.resize = resize; self.selected = selected; self.finish = finish
        }
        @objc func pinch(_ pinch: UIPinchGestureRecognizer) {
            if pinch.state == .began { previousScale = 1; select() }
            if pinch.state == .changed || pinch.state == .ended, let view = pinch.view {
                let factor = pinch.scale / max(0.01, previousScale)
                resize(view.bounds.width * (factor - 1), view.bounds.height * (factor - 1), view.bounds.height)
                previousScale = pinch.scale
            }
            if pinch.state == .ended || pinch.state == .cancelled { finish() }
        }
        @objc func tap() { select() }
        @objc func drag(_ pan: UIPanGestureRecognizer) {
            if pan.state == .began {
                previous = .zero
                let origin = pan.location(in: pan.view)
                let bounds = pan.view?.bounds ?? .zero
                pulling = selected && origin.x > bounds.width - 44 && origin.y > bounds.height - 44
                select()
            }
            if pan.state == .changed || pan.state == .ended {
                let translation = pan.translation(in: pan.view?.window)
                if pulling {
                    resize(translation.x - previous.x, translation.y - previous.y, Double(pan.view?.bounds.height ?? 1))
                } else { move(translation.x - previous.x, translation.y - previous.y) }
                previous = translation
            }
            if pan.state == .ended || pan.state == .cancelled { previous = .zero; finish() }
        }
    }
}

/// The actual slide content, shared by runtime, single-slide preview and direct editing.
struct SplashSlideRenderer: View {
    let slide: SplashSlide
    let viewport: CGSize
    var selected: SplashCanvasItem?
    var select: ((SplashCanvasItem) -> Void)?
    var move: ((SplashCanvasItem, Double, Double) -> Void)?
    var resize: ((SplashCanvasItem, Double, Double, Double) -> Void)?
    var finish: ((SplashCanvasItem) -> Void)?
    @State private var heights: [String: CGFloat] = [:]
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize

    private var style: SplashSlideDesign { slide.resolvedDesign }
    private var width: CGFloat { max(1, min(680, viewport.width - 48)) }
    private var canvasBaseHeight: CGFloat { max(1, viewport.height - 48) }
    private var canvasHeight: CGFloat {
        slide.canvasItems.reduce(canvasBaseHeight) { height, item in
            let halfHeight = (heights[item.id] ?? 0) / 2
            let center = max(halfHeight, canvasBaseHeight * slide.placement(for: item).y)
            return max(height, center + halfHeight + 12)
        }
    }
    private var alignment: Alignment {
        switch style.verticalAlignment { case .top: .top; case .center: .center; case .bottom: .bottom }
    }
    private var textAlignment: TextAlignment {
        switch slide.alignment { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    var body: some View {
        Group {
            if style.freeform {
                ZStack(alignment: .topLeading) {
                    ForEach(slide.canvasItems) { item in
                        let placement = slide.placement(for: item)
                        let itemWidth = width * placement.width
                        element(item, width: itemWidth)
                            .frame(width: itemWidth)
                            .frame(minHeight: placement.height.map { canvasBaseHeight * $0 })
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: SplashMeasurements.self, value: [item.id: proxy.size.height])
                            })
                            .overlay {
                                if selected == item {
                                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                                        .allowsHitTesting(false)
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption.bold()).padding(6).background(.regularMaterial, in: Circle())
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                        .allowsHitTesting(false)
                                }
                            }
                            .contentShape(Rectangle())
                            .modifier(SplashCanvasEditing(select: select.map { action in { action(item) } },
                                move: move.map { action in { dx, dy in action(item, dx, dy) } },
                                width: width, height: canvasBaseHeight,
                                resize: resize.map { action in { dx, dy, height in action(item, dx, dy, height) } },
                                selected: selected == item, finish: finish.map { action in { action(item) } }, grid: style.gridSnapping == true))
                            .modifier(SplashCanvasContainerAccessibility(editing: move != nil, identifier: "SplashCanvas.\(item.id)"))
                            .position(x: centerX(placement, itemWidth: itemWidth), y: max((heights[item.id] ?? 0) / 2, canvasBaseHeight * placement.y))
                            .zIndex(selected == item ? 1 : 0)
                    }
                }
                .frame(width: width, height: canvasHeight)
                .onPreferenceChange(SplashMeasurements.self) { heights = $0 }
                .background {
                    if select != nil && style.gridSnapping == true {
                        Canvas { context, size in
                            var path = Path()
                            for index in 0...20 {
                                let fraction = CGFloat(index) / 20
                                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                                path.addLine(to: CGPoint(x: size.width * fraction, y: canvasBaseHeight))
                                path.move(to: CGPoint(x: 0, y: canvasBaseHeight * fraction))
                                path.addLine(to: CGPoint(x: size.width, y: canvasBaseHeight * fraction))
                            }
                            context.stroke(path, with: .color(Color(splashHex: slide.textColor).opacity(0.18)), lineWidth: 0.5)
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            } else {
                VStack(spacing: 28) {
                    ForEach(slide.canvasItems) { item in
                        element(item, width: width).frame(maxWidth: .infinity)
                    }
                }
                .frame(width: width)
                .frame(minHeight: max(0, viewport.height - 48), alignment: alignment)
            }
        }
        .multilineTextAlignment(textAlignment)
        .foregroundStyle(Color(splashHex: slide.textColor))
        .frame(maxWidth: .infinity).padding(24)
    }
    private func centerX(_ placement: SplashPlacement, itemWidth: CGFloat) -> CGFloat {
        let logical = direction == .rightToLeft ? 1 - placement.x : placement.x
        return min(width - itemWidth / 2, max(itemWidth / 2, width * logical))
    }
    @ViewBuilder private func element(_ item: SplashCanvasItem, width: CGFloat) -> some View {
        switch item {
        case .title: SplashStyledText(text: slide.title ?? "", style: style.title, header: true)
        case .body: SplashStyledText(text: slide.body ?? "", style: style.body)
        case .image:
            if let data = slide.imageData, let image = UIImage(data: data) {
                let limit = width * (style.freeform ? 1 : style.imageWidth)
                let heightLimit = style.freeform ? (slide.placement(for: .image).height.map { canvasBaseHeight * $0 } ?? 320) : 320
                let factor = min(limit / max(1, image.size.width), heightLimit / max(1, image.size.height))
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: image.size.width * factor, height: image.size.height * factor)
                    .clipShape(RoundedRectangle(cornerRadius: style.imageCornerRadius, style: .continuous))
                    .accessibilityLabel(slide.imageDescription)
            } else if let symbol = slide.symbol {
                Image(systemName: symbol)
                    .font(.system(size: min(width * style.imageWidth, typeSize.isAccessibilitySize ? 64 : 96)))
                    .padding(24).accessibilityLabel(slide.imageDescription.isEmpty ? symbol : slide.imageDescription)
            }
        case .feature(let id):
            if let feature = slide.features?.first(where: { $0.id == id }) {
                SplashMockFeatureView(feature: feature, editing: move != nil, boxWidth: style.freeform ? width : nil,
                    minimumHeight: style.freeform ? feature.placement.height.map { canvasBaseHeight * $0 } : nil).id(feature.id)
            }
        case .demonstration:
            if let demo = slide.demonstration { SplashDemonstrationView(demo: demo, editing: move != nil, minimumHeight: style.freeform ? style.demoPlacement.height.map { canvasBaseHeight * $0 } : nil) }
        }
    }
}

/// These are intentionally local replicas: no player, router, account or settings services.
struct SplashMockFeatureView: View {
    let feature: SplashDemoFeature
    var editing = false
    var interaction: () -> Void = {}
    var boxWidth: CGFloat?
    var minimumHeight: CGFloat?
    @State private var on: Bool
    @State private var progress: Double
    @State private var query = ""
    @State private var selectedTab: SplashDemoTab
    @State private var trackNumber = 1
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    init(feature: SplashDemoFeature, editing: Bool = false, boxWidth: CGFloat? = nil, minimumHeight: CGFloat? = nil, interaction: @escaping () -> Void = {}) {
        self.feature = feature; self.editing = editing; self.interaction = interaction
        self.boxWidth = boxWidth; self.minimumHeight = minimumHeight
        _on = State(initialValue: feature.initialValue)
        _progress = State(initialValue: feature.initialProgress)
        _selectedTab = State(initialValue: feature.initialTab ?? .home)
        _query = State(initialValue: feature.initialText ?? "")
    }
    private var accent: Color { Color(splashHex: feature.accentColor) }
    var body: some View {
        Group {
            switch feature.kind {
            case .songRow:
                Button { on.toggle(); interaction() } label: {
                    HStack(spacing: 12) { artwork(size: 48); titles; Spacer(minLength: 8); Image(systemName: on ? "waveform" : "ellipsis") }
                }.accessibilityLabel("Demo song: \(feature.title)").accessibilityValue(on ? "Playing" : "Stopped")
            case .miniPlayer:
                HStack(spacing: 10) {
                    artwork(size: 40); titles; Spacer(minLength: 8)
                    playButton
                    Button { trackNumber += 1; interaction() } label: { Image(systemName: "forward.end.fill") }
                        .accessibilityLabel("Demo next song")
                }
            case .albumCard:
                Button { on.toggle(); interaction() } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        artwork(size: 100); titles
                        if on { Text("Selected").font(.caption).foregroundStyle(accent) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityLabel("Demo album: \(feature.title)")
            case .playPause:
                VStack(spacing: 8) { playButton; Text(feature.title).font(.caption) }
            case .favorite:
                VStack(spacing: 8) {
                    Button { on.toggle(); interaction() } label: { Image(systemName: on ? "heart.fill" : "heart").font(.title) }
                        .foregroundStyle(accent).accessibilityLabel(on ? "Remove demo favorite" : "Add demo favorite")
                    Text(feature.title).font(.caption)
                }
            case .search:
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField(feature.title, text: $query).submitLabel(.search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(interaction).accessibilityLabel("Demo search")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear demo search") }
                }
            case .tabs:
                ViewThatFits(in: .horizontal) {
                    HStack { tabs }
                    VStack { tabs }
                }
            case .settingsToggle:
                Toggle(isOn: Binding(get: { on }, set: { on = $0; interaction() })) { titles }
                    .accessibilityLabel("Demo setting: \(feature.title)")
            case .volume:
                VStack(spacing: 8) {
                    Text(feature.title)
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $progress, in: 0...1, onEditingChanged: { active in if !active { interaction() } })
                            .accessibilityLabel("Demo volume")
                        Image(systemName: "speaker.wave.3.fill")
                    }
                }
            case .lyrics:
                Button { on.toggle(); interaction() } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        SplashStyledText(text: feature.title, style: feature.textStyle).opacity(on ? 0.55 : 1)
                        Text(feature.subtitle).opacity(on ? 1 : 0.55)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityLabel("Select demo lyric line")
            }
        }
        .font(.system(size: feature.textStyle.size * scale, weight: fontWeight, design: fontDesign))
        .buttonStyle(.plain).padding(14)
        .frame(minWidth: boxWidth, minHeight: minimumHeight)
        .foregroundStyle(Color(splashHex: feature.textColor)).tint(accent)
        .background(Color(splashHex: feature.backgroundColor), in: RoundedRectangle(cornerRadius: feature.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: feature.cornerRadius).strokeBorder(feature.highlighted ? accent : .clear, lineWidth: 3))
        .allowsHitTesting(!editing)
        .accessibilityIdentifier("SplashDemo.\(feature.id)")
    }
    private var fontDesign: Font.Design {
        switch feature.textStyle.family { case .system: .default; case .rounded: .rounded; case .serif: .serif; case .monospaced: .monospaced }
    }
    private var fontWeight: Font.Weight {
        switch feature.textStyle.weight { case .regular: .regular; case .medium: .medium; case .semibold: .semibold; case .bold: .bold }
    }
    private var playButton: some View {
        Button { on.toggle(); interaction() } label: { Image(systemName: on ? "pause.fill" : "play.fill").font(.title2) }
            .accessibilityLabel(on ? "Pause demo" : "Play demo").foregroundStyle(accent)
    }
    private var titles: some View {
        VStack(alignment: .leading, spacing: 3) {
            SplashStyledText(text: trackNumber == 1 ? feature.title : "\(feature.title) · \(trackNumber)", style: feature.textStyle)
            Text(feature.subtitle).font(.caption).opacity(0.65)
        }
    }
    private func artwork(size: CGFloat) -> some View {
        Group {
            if let data = feature.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().accessibilityLabel(feature.imageDescription)
            } else { MusicArtworkPlaceholder(cornerRadius: 6).accessibilityLabel("Artwork placeholder") }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: min(feature.cornerRadius, size / 2)))
    }
    private var tabs: some View {
        ForEach(SplashDemoTab.allCases, id: \.self) { tab in
            Button { selectedTab = tab; interaction() } label: {
                VStack(spacing: 5) { Image(systemName: tab.symbol); Text(tab.label).font(.caption2) }
                    .foregroundStyle(selectedTab == tab ? accent : Color(splashHex: feature.textColor))
                    .frame(maxWidth: .infinity)
            }.accessibilityLabel("Demo \(tab.label) tab").accessibilityValue(selectedTab == tab ? "Selected" : "")
        }
    }
}

struct SplashDemonstrationView: View {
    let demo: SplashDemonstration
    var editing = false
    var minimumHeight: CGFloat?
    @State private var index = 0
    private var step: SplashDemoStep { demo.steps[min(index, demo.steps.count - 1)] }
    var body: some View {
        VStack(spacing: 16) {
            Text(step.title).font(.headline)
            Text(step.caption).font(.callout)
            VStack(spacing: 12) {
                ForEach(step.features) { feature in
                    SplashMockFeatureView(feature: feature, editing: editing) {
                        if step.advanceOnInteraction && index < demo.steps.count - 1 { index += 1 }
                    }
                }
            }.id(step.id)
            Text("Demo step \(index + 1) of \(demo.steps.count)").font(.caption)
                .accessibilityIdentifier("SplashDemo.Progress")
            if demo.steps.count > 1 {
                HStack {
                    Button("Previous demo step") { index = max(0, index - 1) }.disabled(index == 0)
                    Button("Next demo step") { index = min(demo.steps.count - 1, index + 1) }.disabled(index == demo.steps.count - 1)
                }.font(.caption).buttonStyle(.bordered).disabled(editing)
            }
        }.padding(16).frame(minHeight: minimumHeight).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("SplashDemo.Sequence")
    }
}
