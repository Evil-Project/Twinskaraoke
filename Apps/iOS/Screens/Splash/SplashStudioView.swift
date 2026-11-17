import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import Observation

struct SplashJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    /// Wraps already encoded JSON bytes for export.
    init(data: Data) { self.data = data }
    /// Validates and encodes a self-contained walkthrough for export.
    init(content: SplashContent) throws {
        try content.validateForPresentation(forRelease: true)
        data = try content.encoded()
    }
    /// Reads and validates imported JSON before creating the document.
    init(configuration: ReadConfiguration) throws {
        let bytes = configuration.file.regularFileContents ?? Data()
        data = try SplashContent.decode(bytes).encoded()
    }
    /// Packages embedded document bytes for the system file exporter.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor @Observable final class SplashStudioModel {
    var draft: SplashContent
    var message: String? { didSet { noticeRevision += 1 } }
    var noticeRevision = 0
    private let directory: URL
    /// Loads the selected bundled walkthrough and any saved draft from the supplied directory.
    init(kind: SplashKind = .install, directory: URL = SplashStateStore.defaultDirectory.appendingPathComponent("Drafts")) {
        self.directory = directory
        draft = (try? SplashBundleLoader.load(kind)) ?? .placeholder(kind)
        loadDraft(kind)
        reserveReleaseNotes()
    }
    /// Returns the local draft path for one walkthrough kind.
    private func file(_ kind: SplashKind) -> URL { directory.appendingPathComponent("\(kind.rawValue).json") }
    /// Loads the saved draft, reporting corrupt content while retaining bundled defaults.
    func loadDraft(_ kind: SplashKind) {
        do { draft = try SplashContent.decode(Data(contentsOf: file(kind)), expectedKind: kind) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { }
        catch { message = "Could not load local draft: \(error.localizedDescription)" }
    }
    /// Validates and atomically saves the draft, optionally announcing success in the notice bubble.
    @discardableResult func saveDraft(announce: Bool = true) -> Bool {
        do {
            let data = try draft.encoded()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            try data.write(to: file(draft.kind), options: .atomic)
            url = file(draft.kind); try url.setResourceValues(values)
            if announce { message = "Draft saved locally." }; return true
        } catch { message = error.localizedDescription; return false }
    }
    /// Saves the outgoing draft before loading the other walkthrough kind.
    func switchMode(_ kind: SplashKind) {
        guard kind != draft.kind, saveDraft(announce: false) else { return }
        draft = (try? SplashBundleLoader.load(kind)) ?? .placeholder(kind)
        message = nil; loadDraft(kind)
        reserveReleaseNotes()
    }
    /// Replaces the draft only after the imported JSON validates for the selected kind.
    func importData(_ data: Data) throws {
        draft = try SplashContent.decode(data, expectedKind: draft.kind)
        reserveReleaseNotes()
    }
    func reserveReleaseNotes() {
        guard draft.kind == .update, draft.slides.first?.releaseNotes == nil, draft.slides.count < 30 else { return }
        draft.slides.insert(.releaseNotesPage(), at: 0)
    }
    func move(_ offsets: IndexSet, to destination: Int) {
        if draft.slides.first?.releaseNotes != nil, offsets.contains(0) || destination == 0 { return }
        draft.slides.move(fromOffsets: offsets, toOffset: destination)
    }
    func delete(_ offsets: IndexSet) {
        let removable = offsets.filter { draft.slides[$0].releaseNotes == nil }
        guard draft.slides.count > removable.count else { message = "Keep at least one slide."; return }
        draft.slides.remove(atOffsets: IndexSet(removable))
        reserveReleaseNotes()
    }
    func binding(for slide: SplashSlide) -> Binding<SplashSlide> {
        var current = slide
        return Binding(
            get: { self.draft.slides.first { $0.id == current.id } ?? current },
            set: { updated in
                guard let index = self.draft.slides.firstIndex(where: { $0.id == current.id }) else { return }
                self.draft.slides[index] = updated
                current = updated
            }
        )
    }
    /// Inserts a copy with a new slide ID without exceeding the thirty-slide limit.
    func duplicate(_ index: Int) {
        guard draft.slides.count < 30, draft.slides[index].releaseNotes == nil else { return }
        var copy = draft.slides[index]; copy.id = UUID().uuidString
        draft.slides.insert(copy, at: index + 1)
    }
    /// Assigns a fresh update identity so a future release can be announced once.
    func newAnnouncement() { guard draft.kind == .update else { return }; draft.id = UUID().uuidString }
}

struct SplashStudioView: View {
    @State private var model: SplashStudioModel
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = SplashJSONDocument(data: Data())
    @State private var preview: SplashContent?
    @State private var confirmReload = false
    @State private var confirmProposal = false
    @Environment(\.scenePhase) private var phase
    /// Uses the supplied Studio model or creates one backed by local draft storage.
    init(model: SplashStudioModel? = nil) {
        _model = State(initialValue: model ?? SplashStudioModel())
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if DeveloperMode.isEnabled {
                List {
                    Section("Content") {
                        Picker("Walkthrough", selection: Binding(get: { model.draft.kind }, set: { kind in model.switchMode(kind) })) {
                            ForEach(SplashKind.allCases) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        TextField("Content ID", text: $model.draft.id)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if model.draft.kind == .update {
                            Toggle("Show Update Walkthrough for This Release", isOn: $model.draft.enabled)
                            Text("Leave this off when a release needs no announcement. Export update.json, replace the bundled source file, then rebuild. First-install onboarding is separate.")
                                .font(.caption)
                            TextField("Target marketing version", text: optional($model.draft.targetVersion))
                                .keyboardType(.numbersAndPunctuation)
                            TextField("Target build (optional)", text: optional($model.draft.targetBuild))
                                .keyboardType(.numbersAndPunctuation)
                            Button("New Announcement", action: model.newAnnouncement)
                            Text("Ordinary edits preserve this ID. Use New Announcement only for a new release announcement.")
                                .font(.caption)
                        }
                        TextField("Next button label", text: $model.draft.nextLabel)
                        TextField("Final button label", text: $model.draft.finalLabel)
                    }
                    Section("Slides — drag to reorder in Edit mode") {
                        ForEach(Array(model.draft.slides.enumerated()), id: \.element.id) { index, slide in
                            if slide.releaseNotes != nil {
                                NavigationLink("Release notes") {
                                    SplashReleaseNotesEditor(slide: model.binding(for: slide))
                                }
                                .moveDisabled(true)
                                .deleteDisabled(true)
                            } else {
                                NavigationLink {
                                    SplashSlideEditor(slide: model.binding(for: slide), allowsWebsite: model.draft.kind == .update)
                                } label: {
                                    VStack(alignment: .leading) {
                                        if slide.website != nil {
                                            Text("Website")
                                        } else {
                                            Text("\(index + 1). \(slide.title ?? "Untitled slide")")
                                        }
                                        Text(slide.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Duplicate") { model.duplicate(index) }.tint(.blue)
                                }
                                .contextMenu { Button("Duplicate") { model.duplicate(index) } }
                            }
                        }
                        .onMove(perform: model.move)
                        .onDelete(perform: model.delete)
                        Button("Add Slide") { model.draft.slides.append(SplashSlide()) }.disabled(model.draft.slides.count >= 30)
                    }
                    Section("Draft and preview") {
                        Button("Save Local Draft") {
                            if model.saveDraft() { AppHaptic.success.play() }
                        }.accessibilityIdentifier("SplashStudio.SaveDraft")
                        Button("Load Bundled Content") { confirmReload = true }
                        if model.draft.kind == .install {
                            Button("Load Proposed Install Walkthrough") { confirmProposal = true }
                        }
                        Button("Import JSON") { importing = true }
                        Button("Preview") {
                            do { try model.draft.validateForPresentation(); preview = model.draft }
                            catch { model.message = error.localizedDescription }
                        }.accessibilityIdentifier("SplashStudio.Preview")
                        Button("Export \(model.draft.kind.rawValue).json") {
                            do { exportDocument = try SplashJSONDocument(content: model.draft); exporting = true }
                            catch { model.message = error.localizedDescription }
                        }.accessibilityIdentifier("SplashStudio.Export")
                    }
                    Section("Publish") {
                        Text("Replace Apps/iOS/Resources/SplashScreens/\(model.draft.kind.rawValue).json in the repository with the exported file, then build and ship a new release. Exporting cannot change an installed app’s bundle.")
                            .font(.callout).textSelection(.enabled)
                    }
                }
                .toolbar { EditButton() }
            } else { Text("Developer mode is required.") }
        }
        .navigationTitle("Splash Screen Studio")
        .navigationBarTitleDisplayMode(.inline)
        .splashNotice($model.message, revision: model.noticeRevision)
        .confirmationDialog("Replace the current install draft with the proposed walkthrough?", isPresented: $confirmProposal, titleVisibility: .visible) {
            Button("Load Proposal", role: .destructive) {
                do { model.draft = try SplashBundledAssets.proposedInstall(); model.message = nil }
                catch { model.message = error.localizedDescription }
            }
        }
        .confirmationDialog("Replace the current draft with bundled content?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Load Bundled Content", role: .destructive) {
                do {
                    model.draft = try SplashBundleLoader.load(model.draft.kind)
                    model.reserveReleaseNotes()
                    model.message = nil
                } catch { model.message = error.localizedDescription }
            }
        }
        .background {
            Color.clear.fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= SplashContent.maxFileBytes else { throw SplashError(message: "JSON exceeds 12 MB.") }
                    try model.importData(Data(contentsOf: url)); model.message = "Imported into the draft."
                } catch {
                    if (error as NSError).code != NSUserCancelledError { model.message = error.localizedDescription }
                }
            }
        }
        .background {
            Color.clear.fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                                     defaultFilename: model.draft.kind.rawValue) { result in
                switch result {
                case .success: model.message = "Export succeeded. Copy the JSON to the source path below and rebuild."
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { model.message = "Export failed: \(error.localizedDescription)" }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview { SplashPreviewView(content: preview) }
        }
        .onChange(of: phase) { _, phase in if phase == .background { model.saveDraft(announce: false) } }
        .onDisappear { model.saveDraft(announce: false) }
    }
    /// Maps empty editor text to a nil optional content field.
    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

struct SplashPreviewView: View {
    let content: SplashContent
    @State private var index = 0
    @State private var highestVisited = 0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        SplashWalkthroughView(content: content, index: index, websiteCompleted: highestVisited > index,
                              back: { index = max(0, index - 1) },
                              next: {
                                  index = min(content.slides.count - 1, index + 1)
                                  highestVisited = max(index, highestVisited)
                              },
                              complete: { dismiss() }, retry: {})
            .safeAreaInset(edge: .top) {
                HStack { Text("Preview"); Spacer(); Button("Exit Preview") { dismiss() } }
                    .padding().background(.regularMaterial)
            }
    }
}

struct SplashSlideEditor: View {
    @Binding var slide: SplashSlide
    var allowsWebsite = false
    @State private var message: String?
    @State private var singlePreview = false
    @State private var arranging = false
    var body: some View {
        Form {
            if allowsWebsite {
                SplashWebsiteEditor(website: $slide.website)
            }
            if slide.website == nil { standardFields }
        }
        .accessibilityIdentifier("SplashStudio.SlideForm")
        .navigationTitle("Edit Slide")
        .splashNotice($message)
        .fullScreenCover(isPresented: $singlePreview) {
            SplashPreviewView(content: SplashContent(kind: .install, id: "single-preview", slides: [slide]))
        }
        .fullScreenCover(isPresented: $arranging) { SplashCanvasEditor(slide: $slide) }
    }
    private var standardFields: some View {
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
