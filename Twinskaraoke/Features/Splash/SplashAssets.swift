import SwiftUI

nonisolated struct SplashBundledAsset: Codable, Identifiable {
    let id: String
    let title: String
    let category: String
    let filename: String
    let description: String
}
enum SplashBundledAssets {
    static func url(_ name: String, bundle: Bundle = .main) -> URL? {
        let path = name as NSString
        let basename = path.deletingPathExtension
        let ext = path.pathExtension
        return bundle.url(forResource: basename, withExtension: ext)
            ?? bundle.url(forResource: basename, withExtension: ext, subdirectory: "SplashScreens/Assets")
            ?? bundle.url(forResource: basename, withExtension: ext, subdirectory: "Resources/SplashScreens/Assets")
            ?? bundle.url(forResource: basename, withExtension: ext, subdirectory: "SplashScreens")
            ?? bundle.url(forResource: basename, withExtension: ext, subdirectory: "Resources/SplashScreens")
    }
    static func catalog(bundle: Bundle = .main) throws -> [SplashBundledAsset] {
        guard let url = url("splash-assets.json", bundle: bundle) else { throw SplashError(message: "Bundled asset catalog is missing.") }
        return try JSONDecoder().decode([SplashBundledAsset].self, from: Data(contentsOf: url))
    }
    static func data(_ asset: SplashBundledAsset, bundle: Bundle = .main) throws -> Data {
        guard let url = url(asset.filename, bundle: bundle) else { throw SplashError(message: "Missing bundled asset: \(asset.title).") }
        let data = try Data(contentsOf: url)
        try SplashContent.validateImage(data, description: asset.description, prefix: "\(asset.title): ")
        return data
    }
    static func proposedInstall(bundle: Bundle = .main) throws -> SplashContent {
        guard let url = url("install-proposed.json", bundle: bundle) else { throw SplashError(message: "Proposed install walkthrough is missing.") }
        return try SplashContent.decode(Data(contentsOf: url), expectedKind: .install)
    }
}
struct SplashAssetGallery: View {
    let selected: (SplashBundledAsset, Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [SplashBundledAsset] = []
    @State private var message: String?
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(Set(assets.map(\.category))).sorted(), id: \.self) { category in
                    Section(category) {
                        ForEach(assets.filter { $0.category == category }) { asset in
                            Button {
                                do { selected(asset, try SplashBundledAssets.data(asset)); dismiss() }
                                catch { message = error.localizedDescription }
                            } label: {
                                HStack {
                                    if let data = try? SplashBundledAssets.data(asset), let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 64)
                                            .accessibilityHidden(true)
                                    }
                                    Text(asset.title).foregroundStyle(.primary)
                                }
                            }.accessibilityIdentifier("SplashAsset.\(asset.id)")
                        }
                    }
                }
            }
            .navigationTitle("Bundled Assets")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .splashNotice($message)
            .task { do { assets = try SplashBundledAssets.catalog() } catch { message = error.localizedDescription } }
        }
    }
}
struct SplashSlideBackground: View {
    let slide: SplashSlide
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(splashHex: slide.backgroundColor)
                if let data = slide.backgroundImageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: slide.backgroundImageFit == .fit ? .fit : .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    Color.black.opacity(slide.backgroundImageDim ?? 0.35)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct SplashBackgroundControls: View {
    @Binding var slide: SplashSlide
    @Binding var message: String?
    var body: some View {
        SplashImageControls(data: $slide.backgroundImageData,
            description: Binding(get: { slide.backgroundImageDescription ?? "Background artwork" }, set: { slide.backgroundImageDescription = $0 }),
            cornerRadius: .constant(0), message: $message, assetLabel: "Choose Background Asset") {
                if slide.backgroundImageDescription == nil { slide.backgroundImageDescription = "Background artwork" }
            }
        Picker("Background Image Fit", selection: Binding(get: { slide.backgroundImageFit ?? .fill }, set: { slide.backgroundImageFit = $0 })) {
            ForEach(SplashBackgroundFit.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        Slider(value: Binding(get: { slide.backgroundImageDim ?? 0.35 }, set: { slide.backgroundImageDim = $0 }), in: 0...0.9, step: 0.05) { Text("Background Dimming") }
            .accessibilityIdentifier("SplashStudio.BackgroundDim")
        Text("Background dimming: \(Int((slide.backgroundImageDim ?? 0.35) * 100))%")
    }
}
