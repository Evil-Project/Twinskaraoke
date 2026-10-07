import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

private struct SplashNoticeModifier: ViewModifier {
    @Binding var message: String?
    var revision: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSuccess(message) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(isSuccess(message) ? Color.green : Color.orange)
                    Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("SplashStudio.Status")
                }
                .padding(16).frame(maxWidth: 520)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.horizontal, 20).padding(.top, 12)
                .onTapGesture { self.message = nil }
                .accessibilityElement(children: .contain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: message)
        .task(id: "\(revision)-\(message ?? "")") {
            guard let notice = message else { return }
            UIAccessibility.post(notification: .announcement, argument: notice)
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            message = nil
        }
    }
    private func isSuccess(_ value: String) -> Bool {
        ["Draft saved locally.", "Imported into the draft.", "Image resized and embedded.", "Test image exported.", "Bundled asset embedded."].contains(value)
        || value.hasPrefix("Export succeeded.")
    }
}
extension View {
    func splashNotice(_ message: Binding<String?>, revision: Int = 0) -> some View {
        modifier(SplashNoticeModifier(message: message, revision: revision))
    }
}

struct SplashTextStyleControls: View {
    @Binding var style: SplashTextStyle
    var body: some View {
        Stepper("Text Size: \(Int(style.size))", value: $style.size, in: 12...72, step: 1)
            .accessibilityIdentifier("SplashStudio.TextSize")
        Picker("Font", selection: $style.family) {
            ForEach(SplashFontFamily.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        Picker("Weight", selection: $style.weight) {
            ForEach(SplashFontWeight.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
    }
}
struct SplashPlacementControls: View {
    @Binding var placement: SplashPlacement
    var grid = false
    var body: some View {
        Slider(value: $placement.x, in: 0.05...0.95, step: grid ? 0.05 : 0.01) { Text("Horizontal Position") }
            .accessibilityIdentifier("SplashStudio.PositionX")
        Text("Horizontal: \(Int(placement.x * 100))%")
        Slider(value: $placement.y, in: 0.05...0.95, step: grid ? 0.05 : 0.01) { Text("Vertical Position") }
            .accessibilityIdentifier("SplashStudio.PositionY")
        Text("Vertical: \(Int(placement.y * 100))%")
        Slider(value: $placement.width, in: 0.2...1, step: 0.05) { Text("Element Width") }.accessibilityIdentifier("SplashStudio.BoxWidth")
        Text("Width: \(Int(placement.width * 100))%")
        Slider(value: Binding(get: { placement.height ?? 0.2 }, set: { placement.height = $0 }), in: 0.05...1.5, step: 0.05) { Text("Minimum Box Height") }
            .accessibilityIdentifier("SplashStudio.BoxHeight")
        Text(placement.height.map { "Minimum height: \(Int($0 * 100))% (content stays readable)" } ?? "Height: Fit to content")
        Button("Fit Box Height to Content") { placement.height = nil }.buttonStyle(.borderless)
        HStack {
            Button("Center Horizontally") { placement.x = 0.5 }
            Button("Center Vertically") { placement.y = 0.5 }
        }.font(.callout).buttonStyle(.borderless)
    }
}
struct SplashHexColorControls: View {
    let title: String
    @Binding var value: String
    var body: some View {
        ColorPicker(title, selection: Binding(get: { Color(splashHex: value) }, set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            value = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }), supportsOpacity: false)
        TextField("\(title) #RRGGBB", text: $value).autocorrectionDisabled()
    }
}

enum SplashImageCompressor {
    static let maxSourceBytes = 30 * 1024 * 1024
    static func compress(_ data: Data, dimension: Int, quality: Double) throws -> Data {
        guard data.count <= maxSourceBytes else { throw SplashError(message: "Select an image under 30 MB.") }
        guard (256...2048).contains(dimension), quality.isFinite, (0.2...0.95).contains(quality) else {
            throw SplashError(message: "Use a dimension from 256–2048 and quality from 20–95%.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let result = UIImage(cgImage: image).jpegData(compressionQuality: quality)
        else { throw SplashError(message: "Unable to decode this image.") }
        guard result.count <= SplashContent.maxImageBytes else {
            throw SplashError(message: "Image exceeds 2 MB. Lower dimension or quality, then compress again.")
        }
        return result
    }
}
struct SplashImageControls: View {
    @Binding var data: Data?
    @Binding var description: String
    @Binding var cornerRadius: Double
    @Binding var message: String?
    var assetLabel = "Choose Bundled Asset"
    var selected: () -> Void = {}
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var choosingAsset = false
    @State private var source: Data?
    @State private var dimension = 1200.0
    @State private var quality = 0.8
    var body: some View {
        Group {
            Button(assetLabel) { choosingAsset = true }
                .sheet(isPresented: $choosingAsset) {
                    SplashAssetGallery { asset, bytes in
                        source = bytes; data = bytes; description = asset.description
                        selected(); message = "Bundled asset embedded."
                    }
                }

            PhotosPicker("Select Image from Photos", selection: $photo, matching: .images)
            Button("Import Image from Files") { importing = true }
                .accessibilityIdentifier("SplashStudio.ImportImage")
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                Text("Embedded image: \(data.count / 1024) KB")
                Slider(value: $dimension, in: 256...2048, step: 64) { Text("Maximum image dimension") }
                Text("Maximum dimension: \(Int(dimension)) px")
                Slider(value: $quality, in: 0.2...0.95) { Text("JPEG quality") }
                Text("JPEG quality: \(Int(quality * 100))%")
                Button("Resize / Compress Image") { compress() }
                Button("Remove Image", role: .destructive) { self.data = nil; source = nil }
            }
            TextField("Image accessibility description", text: $description, axis: .vertical)
        }
        .background {
            Color.clear.fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let bytes = try handle.read(upToCount: SplashImageCompressor.maxSourceBytes + 1) ?? Data()
                    guard bytes.count <= SplashImageCompressor.maxSourceBytes else {
                        throw SplashError(message: "Select an image under 30 MB.")
                    }
                    source = bytes; compress()
                } catch {
                    if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription }
                }
            }
        }
        .onChange(of: photo) { _, selection in
            Task {
                do {
                    guard let bytes = try await selection?.loadTransferable(type: Data.self) else { return }
                    source = bytes; compress(); photo = nil
                } catch { message = error.localizedDescription }
            }
        }
    }
    private func compress() {
        do {
            guard let bytes = source ?? data else { return }
            data = try SplashImageCompressor.compress(bytes, dimension: Int(dimension), quality: quality)
            selected(); message = "Image resized and embedded."
        } catch { message = error.localizedDescription }
    }
}

struct SplashFeatureEditor: View {
    @Binding var feature: SplashDemoFeature
    var showsCanvasPosition = true
    @State private var message: String?
    var body: some View {
        Form {
            Section("Preview") { SplashMockFeatureView(feature: feature).id(feature) }
            Section("App Feature") {
                Picker("Control", selection: $feature.kind) {
                    ForEach(SplashDemoKind.allCases) { Text($0.label).tag($0) }
                }
                TextField("Title / Label", text: $feature.title, axis: .vertical)
                TextField("Subtitle / Description", text: $feature.subtitle, axis: .vertical)
                Toggle("Initially Active", isOn: $feature.initialValue)
                if feature.kind == .tabs {
                    Picker("Initially Selected Tab", selection: Binding(get: { feature.initialTab ?? .home }, set: { feature.initialTab = $0 })) {
                        ForEach(SplashDemoTab.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                if feature.kind == .search {
                    TextField("Initial Search Text", text: Binding(get: { feature.initialText ?? "" }, set: { feature.initialText = $0.isEmpty ? nil : $0 }))
                }
                Slider(value: $feature.initialProgress, in: 0...1) { Text("Initial Slider Value") }
                Toggle("Highlight This Control", isOn: $feature.highlighted)
            }
            Section("Font") { SplashTextStyleControls(style: $feature.textStyle) }
            Section("Appearance") {
                SplashHexColorControls(title: "Accent", value: $feature.accentColor)
                SplashHexColorControls(title: "Background", value: $feature.backgroundColor)
                SplashHexColorControls(title: "Text", value: $feature.textColor)
                Slider(value: $feature.cornerRadius, in: 0...80, step: 1) { Text("Feature Corner Radius") }
                Text("Rounded corners: \(Int(feature.cornerRadius))")
            }
            if [.songRow, .miniPlayer, .albumCard].contains(feature.kind) {
                Section("Artwork") {
                    SplashImageControls(data: $feature.imageData, description: $feature.imageDescription, cornerRadius: $feature.cornerRadius, message: $message)
                }
            }
            if showsCanvasPosition {
                Section("Canvas Position") { SplashPlacementControls(placement: $feature.placement) }
            }
        }.navigationTitle(feature.kind.label).splashNotice($message)
    }
}

struct SplashDemonstrationEditor: View {
    @Binding var demo: SplashDemonstration
    var body: some View {
        List {
            Section("Interactive Preview") { SplashDemonstrationView(demo: demo).id(demo) }
            Section("Steps") {
                ForEach(Array(demo.steps.enumerated()), id: \.element.id) { index, step in
                    NavigationLink("\(index + 1). \(step.title)") { SplashDemoStepEditor(step: $demo.steps[index]) }
                }
                .onMove { demo.steps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { if demo.steps.count - $0.count >= 1 { demo.steps.remove(atOffsets: $0) } }
                Button("Add Demo Step") { demo.steps.append(SplashDemoStep()) }.disabled(demo.steps.count >= 12)
            }
            Section {
                Text("Each step shows local mock app controls. Enable advance after interaction to reveal the next configured step when a control is used. Demo step buttons also allow replay.").font(.caption)
            }
        }.navigationTitle("Interaction Slideshow").toolbar { EditButton() }
    }
}
struct SplashDemoStepEditor: View {
    @Binding var step: SplashDemoStep
    var body: some View {
        List {
            Section("Step") {
                TextField("Step Title", text: $step.title)
                TextField("Instruction / Caption", text: $step.caption, axis: .vertical)
                Toggle("Advance After Interaction", isOn: $step.advanceOnInteraction)
            }
            Section("App Controls") {
                ForEach(Array(step.features.enumerated()), id: \.element.id) { index, feature in
                    NavigationLink(feature.kind.label) { SplashFeatureEditor(feature: $step.features[index], showsCanvasPosition: false) }
                }
                .onMove { step.features.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { if step.features.count - $0.count >= 1 { step.features.remove(atOffsets: $0) } }
                Menu("Add App Feature") {
                    ForEach(SplashDemoKind.allCases) { kind in Button(kind.label) { step.features.append(SplashDemoFeature(kind: kind)) } }
                }.disabled(step.features.count >= 12)
            }
        }.navigationTitle("Demo Step").toolbar { EditButton() }
    }
}
