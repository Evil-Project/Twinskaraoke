import SwiftUI
import UIKit

struct SplashStandardSlideFields: View {
    @Binding var slide: SplashSlide
    @Binding var message: String?
    @Binding var singlePreview: Bool
    @Binding var arranging: Bool

    var body: some View {
        Group {
            Section("Live design") {
                Button("Preview This Slide") {
                    do {
                        try SplashContent(kind: .install, id: "single-preview", slides: [slide]).validate()
                        singlePreview = true
                    } catch { message = error.localizedDescription }
                }.accessibilityIdentifier("SplashStudio.SinglePreview")
                Button("Arrange on Canvas") {
                    var value = slide.resolvedDesign; value.freeform = true; slide.design = value
                    arranging = true
                }.accessibilityIdentifier("SplashStudio.Arrange")
                Text("Drag individual items and edit them live. Positions adapt to the screen size.")
                    .font(.caption)
            }
            Section("Text") {
                TextField("Stable slide ID", text: $slide.id).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Title (optional)", text: optional($slide.title), axis: .vertical)
                TextField("Body (optional)", text: optional($slide.body), axis: .vertical).lineLimit(4...12)
            }
            Section("Design") {
                Picker("Layout", selection: $slide.layout) {
                    ForEach(SplashLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Text alignment", selection: $slide.alignment) {
                    ForEach(SplashAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Typography", selection: $slide.typography) {
                    ForEach(SplashTypography.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .onChange(of: slide.typography) { _, value in
                    var design = slide.resolvedDesign
                    let preset = SplashSlideDesign(typography: value)
                    design.title = preset.title; design.body = preset.body
                    slide.design = design
                }
                Picker("Vertical Content Alignment", selection: design(\.verticalAlignment)) {
                    ForEach(SplashVerticalAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.accessibilityIdentifier("SplashStudio.VerticalAlignment")
                Toggle("Freeform Positions", isOn: design(\.freeform))
                ColorPicker("Background", selection: color($slide.backgroundColor), supportsOpacity: false)
                TextField("Background #RRGGBB", text: $slide.backgroundColor).autocorrectionDisabled()
                ColorPicker("Text", selection: color($slide.textColor), supportsOpacity: false)
                TextField("Text #RRGGBB", text: $slide.textColor).autocorrectionDisabled()
            }
            Section("Title Font") { SplashTextStyleControls(style: design(\.title)) }
            Section("Body Font") { SplashTextStyleControls(style: design(\.body)) }
            Section("Image or SF Symbol") {
                TextField("SF Symbol (optional)", text: Binding(get: { slide.symbol ?? "" }, set: {
                    slide.symbol = $0.isEmpty ? nil : $0
                    if !$0.isEmpty { slide.imageData = nil }
                })).textInputAutocapitalization(.never).autocorrectionDisabled()
                SplashImageControls(data: $slide.imageData, description: $slide.imageDescription,
                                    cornerRadius: design(\.imageCornerRadius), message: $message) { slide.symbol = nil }
                Slider(value: design(\.imageWidth), in: 0.2...1, step: 0.05) { Text("Image Width") }
                Text("Image width: \(Int(slide.resolvedDesign.imageWidth * 100))%")
                Slider(value: design(\.imageCornerRadius), in: 0...80, step: 1) { Text("Rounded Image Corners") }
                    .accessibilityIdentifier("SplashStudio.Corners")
                Text("Rounded corners: \(Int(slide.resolvedDesign.imageCornerRadius))")
            }
            Section("Background Image") { SplashBackgroundControls(slide: $slide, message: $message) }
            Section("App Features") {
                ForEach(slide.features ?? []) { feature in
                    if let index = slide.features?.firstIndex(where: { $0.id == feature.id }) {
                        NavigationLink(feature.kind.label) {
                            SplashFeatureEditor(feature: Binding(get: { slide.features![index] }, set: { slide.features?[index] = $0 }))
                        }
                    }
                }
                .onDelete { slide.features?.remove(atOffsets: $0) }
                Menu("Add App Feature") {
                    ForEach(SplashDemoKind.allCases) { kind in
                        Button(kind.label) {
                            if slide.features == nil { slide.features = [] }
                            slide.features?.append(SplashDemoFeature(kind: kind))
                        }
                    }
                }.disabled((slide.features?.count ?? 0) >= 12)
                Text("These are interactive demo copies of Twinskaraoke controls. They never change real playback, favorites or settings.").font(.caption)
            }
            Section("Interaction Slideshow") {
                if slide.demonstration != nil {
                    NavigationLink("Edit Demo Steps") {
                        SplashDemonstrationEditor(demo: Binding(get: { slide.demonstration! }, set: { slide.demonstration = $0 }))
                    }
                    Button("Remove Interaction Slideshow", role: .destructive) { slide.demonstration = nil }
                } else {
                    Button("Add Interaction Slideshow") { slide.demonstration = SplashDemonstration() }
                }
            }
        }
    }

    /// Binds an optional slide design field through its resolved default design.
    private func design<T>(_ key: WritableKeyPath<SplashSlideDesign, T>) -> Binding<T> {
        Binding(get: { slide.resolvedDesign[keyPath: key] }, set: { value in
            var design = slide.resolvedDesign; design[keyPath: key] = value; slide.design = design
        })
    }
    /// Maps empty editor text to a nil optional content field.
    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
    /// Converts between stored hexadecimal colors and the native color picker binding.
    private func color(_ binding: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(splashHex: binding.wrappedValue) }, set: { value in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(value).getRed(&r, green: &g, blue: &b, alpha: &a)
            binding.wrappedValue = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        })
    }
}
