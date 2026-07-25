import SwiftUI

#if canImport(UIKit)
    import SDWebImage
    import UIKit
#endif

struct ArtDetailView: View {
    let art: GalleryArt
    let artist: GalleryArtist
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var showFullScreen = false
    @State private var saveStatus: ArtworkSaveStatus = .idle
    @State private var saveGeneration = 0
    @State private var appeared = false
    private var fullResURL: URL? {
        art.fullHDImageURL ?? art.imageURL
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ArtworkDetailHero(
                    art: art,
                    artist: artist,
                    fullResURL: fullResURL,
                    onOpen: openFullScreen,
                    onSave: saveImage
                )
                .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.97))
                .opacity(appeared ? 1 : 0)

                VStack(alignment: .leading, spacing: 18) {
                    ArtworkActionStrip(
                        url: fullResURL,
                        saveStatus: saveStatus,
                        onOpen: openFullScreen,
                        onSave: saveImage
                    )

                    ArtworkDetailMetadata(art: art)
                }
                .padding(.horizontal, 16)
                .offset(y: reduceMotion ? 0 : (appeared ? 0 : 16))
                .opacity(appeared ? 1 : 0)
            }
            .padding(.bottom, 24)
        }
        .smoothScrolling()
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .background {
            ArtworkDetailAmbientBackground(art: art)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            ZoomableImageViewer(
                url: fullResURL,
                lowResURL: art.blurPreviewURL,
                saveStatus: $saveStatus,
                onSave: saveImage,
                title: artist.name,
                subtitle: artist.socialLink
            )
        }
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(AppMotion.standard) {
                appeared = true
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            if reduceMotion {
                withAnimation(nil) {
                    appeared = true
                }
            }
        }
        .onChange(of: saveStatus) { _, status in
            switch status {
            case .success:
                AppHaptic.success.play()
            case .failed:
                AppHaptic.error.play()
            case .saving, .idle:
                break
            }
        }
    }

    private func openFullScreen() {
        AppHaptic.medium.play()
        showFullScreen = true
    }

    private func saveImage() {
        guard !saveStatus.isSaving else { return }
        guard let url = fullResURL else { return }
        AppHaptic.selection.play()
        saveStatus = .saving
        saveGeneration &+= 1
        let generation = saveGeneration
        #if canImport(UIKit)
            // RemoteArtworkImage already downloaded this exact URL into the
            // shared SDWebImage memory cache; reuse it instead of re-downloading.
            if let cached = SDImageCache.shared.imageFromMemoryCache(forKey: url.absoluteString) {
                saveLoadedImage(cached, generation: generation)
                return
            }
        #endif
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                #if canImport(UIKit)
                    if let data, let image = UIImage(data: data) {
                        saveLoadedImage(image, generation: generation)
                        return
                    }
                #endif
                saveStatus = .failed(error?.localizedDescription ?? "Couldn't save")
                resetSaveStatusLater(generation: generation)
            }
        }.resume()
    }

    #if canImport(UIKit)
        private func saveLoadedImage(_ image: UIImage, generation: Int) {
            ImageSaver.shared.save(image: image) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        saveStatus = .success
                    case let .failure(err):
                        saveStatus = .failed(err.localizedDescription)
                    }
                    resetSaveStatusLater(generation: generation)
                }
            }
        }
    #endif

    private func resetSaveStatusLater(generation: Int) {
        // A second save may start before this timer fires; only reset the
        // status that belongs to this save cycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard saveGeneration == generation else { return }
            saveStatus = .idle
        }
    }
}
