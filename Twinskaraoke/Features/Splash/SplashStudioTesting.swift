#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

/// Explicit debug-only launch mode, with drafts isolated from the user's Studio.
enum SplashStudioTestingFixtures {
    static var content: SplashContent {
        var content = SplashContent.placeholder(.install)
        var slide = content.slides[0]
        slide.design = SplashSlideDesign()
        var player = SplashDemoFeature(kind: .miniPlayer); player.id = "demo-player"
        var favorite = SplashDemoFeature(kind: .favorite); favorite.id = "demo-favorite"
        slide.features = [player, favorite]
        var first = SplashDemoStep(); first.id = "demo-step-one"; first.advanceOnInteraction = true
        var play = SplashDemoFeature(kind: .playPause); play.id = "demo-step-play"
        first.features = [play]
        var second = SplashDemoStep(); second.id = "demo-step-two"
        var row = SplashDemoFeature(kind: .songRow); row.id = "demo-step-row"; row.initialValue = true
        second.features = [row]
        slide.demonstration = SplashDemonstration(steps: [first, second])
        content.slides[0] = slide
        return content
    }
    static let model: SplashStudioModel = {
        DeveloperMode.isEnabled = true
        let directory = SplashStateStore.defaultDirectory.appendingPathComponent("UITest/DesignStudioDrafts")
        if ProcessInfo.processInfo.arguments.contains("-UITestSplashStudioReset") { try? FileManager.default.removeItem(at: directory) }
        let model = SplashStudioModel(directory: directory)
        if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("install.json").path) { model.draft = content }
        return model
    }()
    static var image: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 96)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }.pngData()!
    }
}
private struct SplashTestingImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    var data: Data
    /// Wraps image fixture bytes for the system file importer/exporter tests.
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    /// Packages embedded document bytes for the system file exporter.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SplashStudioTestingHost: View {
    @State private var exporting = false
    var body: some View {
        NavigationStack {
            SplashStudioView(model: SplashStudioTestingFixtures.model)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Test Image") { exporting = true }.accessibilityLabel("Export Test Image")
                    }
                }
        }
        .background {
            Color.clear.fileExporter(isPresented: $exporting, document: SplashTestingImageDocument(data: SplashStudioTestingFixtures.image),
                                     contentType: .png, defaultFilename: "walkthrough-test-image") { result in
                switch result {
                case .success: SplashStudioTestingFixtures.model.message = "Test image exported."
                case .failure(let error): SplashStudioTestingFixtures.model.message = error.localizedDescription
                }
            }
        }
    }
}
#endif
