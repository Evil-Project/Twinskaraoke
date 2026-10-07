import SwiftUI

struct SplashCanvasEditor: View {
    @Binding var slide: SplashSlide
    @State private var selected: SplashCanvasItem = .title
    @State private var previewing = false
    @State private var inspecting = false
    @State private var inspectorDetent: PresentationDetent = .large
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    private var choices: [SplashCanvasItem] {
        var items: [SplashCanvasItem] = [.title, .body, .image]
        items += (slide.features ?? []).map { .feature($0.id) }
        if slide.demonstration != nil { items.append(.demonstration) }
        return items
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ScrollView {
                        SplashSlideRenderer(slide: slide, viewport: proxy.size, selected: selected,
                            select: { selected = $0 }, move: { item, dx, dy in
                                var placement = slide.placement(for: item)
                                placement.move(dx: dx, dy: dy)
                                slide.setPlacement(placement, for: item)
                            }, resize: { item, dx, dy, height in
                                var placement = slide.placement(for: item)
                                placement.resize(dx: dx, dy: dy, measuredHeight: height)
                                slide.setPlacement(placement, for: item)
                            }, finish: { item in
                                guard slide.resolvedDesign.gridSnapping == true else { return }
                                var placement = slide.placement(for: item); placement.snapToGrid()
                                slide.setPlacement(placement, for: item)
                            })
                    }
                }
                .clipped().contentShape(Rectangle())
                .background(SplashSlideBackground(slide: slide))
                .accessibilityIdentifier("SplashStudio.Canvas")
            }
            .navigationTitle("Slide Canvas").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Preview Slide") {
                        do {
                            try SplashContent(kind: .install, id: "single-preview", slides: [slide]).validate()
                            previewing = true
                        } catch { message = error.localizedDescription }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Toggle(isOn: designGrid) { Image(systemName: "grid") }
                        .accessibilityLabel("Snap to Grid")
                        .toggleStyle(.button)
                        .accessibilityIdentifier("SplashStudio.Grid")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Edit Selected Item") { inspecting = true }
                        .accessibilityIdentifier("SplashStudio.EditSelected")
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu("Add App Feature", systemImage: "plus") {
                        ForEach(SplashDemoKind.allCases) { kind in
                            Button(kind.label) {
                                let feature = SplashDemoFeature(kind: kind)
                                if slide.features == nil { slide.features = [] }
                                slide.features?.append(feature); selected = .feature(feature.id)
                            }
                        }
                    }.labelStyle(.iconOnly).disabled((slide.features?.count ?? 0) >= 12)
                }
            }
            .sheet(isPresented: $inspecting) {
                NavigationStack {
                    inspector
                        .navigationTitle("Edit Selected Item")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done Editing") { inspecting = false }
                            }
                        }
                        .splashNotice($message)
                }
                .presentationDetents([.medium, .large], selection: $inspectorDetent)
                .presentationDragIndicator(.visible)
            }
            .splashNotice($message)
            .fullScreenCover(isPresented: $previewing) {
                SplashPreviewView(content: SplashContent(kind: .install, id: "single-preview", slides: [slide]))
            }
        }
    }
    private var inspector: some View {
        Form {
            Section {
                Text("Tap to select. Drag to move. Pinch or pull the lower-right corner to resize. Grid snapping aligns to 5% steps when a gesture ends.").font(.caption)
            }
            Section("Selection") {
                Picker("Selected Item", selection: $selected) {
                    ForEach(choices) { item in Text(label(item)).tag(item) }
                }.accessibilityIdentifier("SplashStudio.CanvasSelection")
                Toggle("Freeform Positions", isOn: design(\.freeform))
                Toggle("Snap to Grid", isOn: designGrid)
                if slide.resolvedDesign.freeform {
                    SplashPlacementControls(placement: Binding(get: { slide.placement(for: selected) }, set: { slide.setPlacement($0, for: selected) }), grid: slide.resolvedDesign.gridSnapping == true)
                } else {
                    Picker("Vertical Content Alignment", selection: design(\.verticalAlignment)) {
                        ForEach(SplashVerticalAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
            }
            switch selected {
            case .title:
                Section("Title") {
                    TextField("Title", text: text(\.title), axis: .vertical)
                    SplashTextStyleControls(style: design(\.title))
                }
            case .body:
                Section("Body") {
                    TextField("Body", text: text(\.body), axis: .vertical).lineLimit(2...6)
                    SplashTextStyleControls(style: design(\.body))
                }
            case .image:
                Section("Image / Symbol") {
                    TextField("SF Symbol", text: Binding(get: { slide.symbol ?? "" }, set: { value in
                        slide.symbol = value.isEmpty ? nil : value
                        if !value.isEmpty {
                            slide.imageData = nil
                            if slide.layout == .textOnly { slide.layout = .imageAbove }
                        }
                    })).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SplashImageControls(data: $slide.imageData, description: $slide.imageDescription,
                                        cornerRadius: design(\.imageCornerRadius), message: $message) {
                        slide.symbol = nil
                        if slide.layout == .textOnly { slide.layout = .imageAbove }
                    }
                    Slider(value: design(\.imageCornerRadius), in: 0...80, step: 1) { Text("Rounded Image Corners") }
                    Text("Rounded corners: \(Int(slide.resolvedDesign.imageCornerRadius))")
                }
            case .feature(let id):
                if let index = slide.features?.firstIndex(where: { $0.id == id }) {
                    Section("App Feature") {
                        TextField("Label", text: Binding(get: { slide.features![index].title }, set: { slide.features?[index].title = $0 }))
                        NavigationLink("Edit All Feature Options") {
                            SplashFeatureEditor(feature: Binding(get: { slide.features![index] }, set: { slide.features?[index] = $0 }))
                        }
                        Button("Remove Feature", role: .destructive) { slide.features?.remove(at: index); selected = .title }
                    }
                }
            case .demonstration:
                if slide.demonstration != nil {
                    Section("Interaction Slideshow") {
                        NavigationLink("Edit Demo Steps") {
                            SplashDemonstrationEditor(demo: Binding(get: { slide.demonstration! }, set: { slide.demonstration = $0 }))
                        }
                    }
                }
            }
            Section("Background Image") { SplashBackgroundControls(slide: $slide, message: $message) }
            Section("Slide Colors and Alignment") {
                SplashHexColorControls(title: "Background", value: $slide.backgroundColor)
                SplashHexColorControls(title: "Text", value: $slide.textColor)
                Picker("Text Alignment", selection: $slide.alignment) {
                    ForEach(SplashAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
        }
        .accessibilityIdentifier("SplashStudio.CanvasInspector")
    }
    private var designGrid: Binding<Bool> {
        Binding(get: { slide.resolvedDesign.gridSnapping == true }, set: { value in
            var design = slide.resolvedDesign; design.gridSnapping = value; slide.design = design
            if value {
                for item in slide.canvasItems {
                    var placement = slide.placement(for: item); placement.snapToGrid()
                    slide.setPlacement(placement, for: item)
                }
            }
        })
    }
    private func label(_ item: SplashCanvasItem) -> String {
        if case .feature(let id) = item { return slide.features?.first { $0.id == id }?.kind.label ?? item.label }
        return item.label
    }
    private func design<T>(_ key: WritableKeyPath<SplashSlideDesign, T>) -> Binding<T> {
        Binding(get: { slide.resolvedDesign[keyPath: key] }, set: { value in
            var design = slide.resolvedDesign; design[keyPath: key] = value; slide.design = design
        })
    }
    private func text(_ key: WritableKeyPath<SplashSlide, String?>) -> Binding<String> {
        Binding(get: { slide[keyPath: key] ?? "" }, set: { slide[keyPath: key] = $0.isEmpty ? nil : $0 })
    }
}
